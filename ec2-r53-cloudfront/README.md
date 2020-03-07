# EC2 routed by R53 and served by Cloud Front

Running:

```
  terraform init
```

```
  terraform plan \
    -var="host=foo.bar.com"
    -var="domain=bar.com."
    -var="ssh-key=$(cat ~/.ssh/id_rsa.pub)"
```

```
  terraform apply \
    -var="host=foo.bar.com"
    -var="domain=bar.com."
    -var="ssh-key=$(cat ~/.ssh/id_rsa.pub)"
```
