# test-athg

test-athg service, onboarded via the Azure golden path.

## Architecture

This service runs on Azure Container Apps as a container pulled from Azure Container Registry. CPU, memory, restart, and downtime metric alerts are wired to the shared platform inbox by default, or to this app's own Action Group if an alert email was set at onboarding.



## Endpoints

- `/health` returns service health.
- Any other endpoints are defined in this app's own source.


## Deployment

Push to `main`. Automated tests must pass before CI versions, scans, and builds the image. Token-free Semgrep Community Edition analyzes source independently from the Trivy container-image scan and publishes its normalized report to `security/semgrep-latest.json`. The infra workflow provisions or updates the Azure resources defined in `iac/infra/`.

Production can be rolled back from the **Roll back production** workflow by selecting an existing semantic version. Rollback never rebuilds source: it verifies and deploys the immutable ACR image, checks the Container App revision health, and restores the previous image if verification fails.

The generated Container App uses `Single` revision mode. The rollback workflow verifies that invariant before mutation so restoration returns all traffic to the previous healthy image; it refuses multi-revision traffic configurations rather than claiming a false recovery.
