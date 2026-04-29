# Example Client Deployment

Template for onboarding new clients.

## Local Scan (no cloud infra)

```bash
cp -r deployments/_example deployments/<client>
# Edit targets.txt with client external targets
./scanner/scan.py <client>
```

## Automated Cloud Deployment

1. Copy this directory to `deployments/<client>/`
2. Update `terraform.tfvars` with client values
3. Update `backend.tf` with client state bucket
4. Replace `targets.txt` with client targets
5. Create Terraform state bucket (one-time)
6. Open PR → merge → `terraform apply`
