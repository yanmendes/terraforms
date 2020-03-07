# S3 served by CloudFront

Running:

```
  terraform init
```

```
  terraform plan \
    -var="host=foo.bar.com"
    -var="domain=bar.com."
    -var="s3Key=s0M3_Cr4zY_S3Cr31"
```

```
  terraform apply \
    -var="host=foo.bar.com"
    -var="domain=bar.com."
    -var="s3Key=s0M3_Cr4zY_S3Cr31"
```
