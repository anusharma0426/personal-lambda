# GitHub Actions Migration

This repository can move from GitLab CI to GitHub Actions without changing the Terraform entry points. The new workflows keep using `make init`, `make plan`, and `make apply` from the existing `Makefile`.

## Files Added

- `.github/workflows/deploy.yml`
- `.github/workflows/terraform-deploy.yml`

`deploy.yml` is the parent pipeline. It runs secret detection, then promotes `dev -> sit -> uat -> prd`.

`terraform-deploy.yml` is the reusable workflow that runs Terraform plan/apply for a single workspace.

## Required GitHub Secrets

Set these repository secrets for GitLab registry access:

- `GITLAB_REGISTRY_USERNAME`
- `GITLAB_REGISTRY_TOKEN`

Set these environment-specific or repository secrets for each deployment stage:

- `DEV_AWS_BOOTSTRAP_ROLE_ARN`
- `DEV_AWS_ACCOUNT_ID`
- `DEV_AWS_ROLE`
- `DEV_AWS_ECR_ACCOUNT_ID`
- `DEV_AWS_ECR_REPO`
- `SIT_AWS_BOOTSTRAP_ROLE_ARN`
- `SIT_AWS_ACCOUNT_ID`
- `SIT_AWS_ROLE`
- `SIT_AWS_ECR_ACCOUNT_ID`
- `SIT_AWS_ECR_REPO`
- `UAT_AWS_BOOTSTRAP_ROLE_ARN`
- `UAT_AWS_ACCOUNT_ID`
- `UAT_AWS_ROLE`
- `UAT_AWS_ECR_ACCOUNT_ID`
- `UAT_AWS_ECR_REPO`
- `PRD_AWS_BOOTSTRAP_ROLE_ARN`
- `PRD_AWS_ACCOUNT_ID`
- `PRD_AWS_ROLE`
- `PRD_AWS_ECR_ACCOUNT_ID`
- `PRD_AWS_ECR_REPO`

## GitHub Environments

Create these GitHub environments:

- `dev`
- `sit`
- `uat`
- `prd`

Recommended protection rules:

- `dev`: optional reviewers
- `sit`: required reviewers if you want manual promotion
- `uat`: required reviewers
- `prd`: required reviewers and branch/tag restrictions

The reusable workflow binds the `apply` job to the GitHub environment, so approvals happen before `make apply` runs.

## AWS Role Design

The current repository already assumes a deployment role inside `.deploy/scripts/assume-role.sh`.

To preserve that behavior, GitHub Actions should first assume a bootstrap role through OIDC, then the existing script assumes the final deployment role from `AWS_ACCOUNT_ID` and `AWS_ROLE`.

Recommended pattern:

1. Add GitHub's OIDC provider to AWS IAM.
2. Create one bootstrap role per environment, or one shared bootstrap role with access controls.
3. Allow the bootstrap role to call `sts:AssumeRole` on the final deployment role used by this repo.
4. Store the bootstrap role ARN in `*_AWS_BOOTSTRAP_ROLE_ARN`.

## Registry Access

This repository still uses container images from `registry.cochlear.dev`, so GitHub runners must be able to reach and authenticate to that registry.

If GitHub-hosted runners cannot reach the registry or internal network, move these workflows to self-hosted runners and update `runs-on` accordingly.

## Trigger Mapping

The new GitHub workflow maps the current GitLab behavior like this:

- `pull_request` to `main`: secret detection only
- `push` to `main`: deploy `dev -> sit -> uat`
- `push` tag `b*`: deploy `dev -> sit -> uat`
- `push` tag `v*`: deploy `dev -> sit -> uat -> prd`
- `workflow_dispatch`: manual run with `target_environment`

## First Migration Test

Recommended sequence:

1. Create GitHub environments and secrets.
2. Configure AWS OIDC bootstrap role trust.
3. Run `workflow_dispatch` for `dev` only.
4. Confirm `make init`, `make plan`, artifact upload, artifact download, and `make apply` succeed.
5. Add environment approvals for `sit`, `uat`, and `prd`.
6. Switch production release tags after at least one successful non-production promotion.

## Known Assumptions

- The workflows install a `docker-compose` compatibility wrapper because the repository still calls `docker-compose` directly.
- The workflows generate GitLab-compatible variables such as `CI_COMMIT_SHORT_SHA`, `ECR_TAG`, and `CI_JOB_TOKEN` so the existing `Makefile` continues to work.
- Secret detection is run directly with the existing Gitleaks image from the GitLab registry instead of calling `make security-analyzer`, because that target also validates AWS env files that are not required for a scan.