#### Variable definitions
owner                   = "rosskirkpatrick" # owner tag value for AWS to avoid cleanup by cloud custodian
aws_credentials_file    = "/Users/rosskirk/.aws/credentials" # full path to your local AWS credentials file
aws_profile             = "default" # name of the profile to use from the AWS credentials file
aws_region              = "us-east-1" # pick your preferred aws region
vpc_name                = "ross-scale-testing" # the name of the VPC that you want to create
prefix                  = "ross"