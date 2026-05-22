import logging
import boto3
import os
import json
import uuid
import datetime

logger = logging.getLogger("")

def lambda_handler(event, context):
    service_client = boto3.client('secretsmanager')
    arn = os.environ['SECRET_ID']

    pending_version = get_secret_version_id_by_stage(arn, "AWSPENDING")
    logger.info(f'pending_version: {pending_version}')

    if pending_version is None:
        pending_version = str(uuid.uuid4())

    create_secret(service_client, arn, pending_version)
    set_secret(service_client, arn, pending_version)
    test_secret(service_client, arn, pending_version)
    finish_secret(service_client, arn, pending_version)


def get_secret_version_id_by_stage(secret_id, version_stage):
    secrets_manager_client = boto3.client('secretsmanager')
    metadata = secrets_manager_client.describe_secret(SecretId=secret_id)
    versions = metadata['VersionIdsToStages']
    for version in versions:
        if version_stage in versions[version]:
            return version
    return None


def create_secret(service_client, arn, pending_version):
    try:
        service_client.get_secret_value(
            SecretId=arn,
            VersionId=pending_version,
            VersionStage="AWSPENDING"
        )
        logger.info("createSecret: Secret already exists for %s." % arn)
    except Exception:
        new_secret = {"value": f'secret_{datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}'}
        service_client.put_secret_value(
            SecretId=arn,
            ClientRequestToken=pending_version,
            SecretString=json.dumps(new_secret),
            VersionStages=["AWSPENDING"]
        )
        logger.info("createSecret: Successfully put secret for ARN %s version %s." % (arn, pending_version))


def set_secret(service_client, arn, pending_version):
    # Implement service-specific logic here (e.g. update a database password).
    logger.info("setSecret: Successfully set secret for %s." % arn)


def test_secret(service_client, arn, pending_version):
    # Implement validation logic here (e.g. test DB login with AWSPENDING value).
    logger.info("testSecret: Successfully tested secret for %s." % arn)


def finish_secret(service_client, arn, pending_version):
    try:
        current_version_id = get_secret_version_id_by_stage(arn, "AWSCURRENT")
        service_client.update_secret_version_stage(
            SecretId=arn,
            VersionStage="AWSCURRENT",
            MoveToVersionId=pending_version,
            RemoveFromVersionId=current_version_id
        )
        service_client.update_secret_version_stage(
            SecretId=arn,
            VersionStage="AWSPENDING",
            RemoveFromVersionId=pending_version
        )
        logger.info("finishSecret: Successfully set AWSCURRENT for secret %s." % arn)
    except Exception as e:
        logger.error("finishSecret: Failed to set AWSCURRENT for secret %s. Error: %s" % (arn, str(e)))
        raise
