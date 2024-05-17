terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"                                      # cheapest region with low latency: eu-west-1
}

resource "aws_s3_bucket" "local-bucket-name" {
  bucket = "nachtje-terraform-demo" 
  force_destroy = true                                      # also destroys the bucket if there are files in it
}

resource "aws_s3_object" "data-upload" {
  bucket = aws_s3_bucket.local-bucket-name.id
  key    = "data/dataset_immo.csv"                          # this should be the path expected on your bucket!
  source = "../data/dataset_immo.csv"                       # relative path to your local file
  etag = filemd5("../data/dataset_immo.csv")                # relative path to your local file
}

resource "aws_s3_object" "script-upload" {
  bucket = aws_s3_bucket.local-bucket-name.id
  key    = "script/demo_ray.py"                           # this should be the path expected on your bucket!
  source = "../script/demo_ray.py"                        # relative path to your local file
  etag = filemd5("../script/demo_ray.py")                 # relative path to your local file
}

resource "aws_glue_job" "local-job-name" {
  name         = "demo-ray-nachtje"
  role_arn     = aws_iam_role.glue_role.arn               # your glue role local name
  glue_version = "4.0"
  description  = "foo"
  worker_type  = "Z.2X"                                   # only machine available for ray jobs
  number_of_workers = 5                                   # minumum of 2. Stick with a low number to avoid unexpected costs

  command {
    name            = "glueray"
    python_version  = "3.9"
    runtime         = "Ray2.4"
    script_location = "s3://${aws_s3_bucket.local-bucket-name.bucket}/script/demo_ray.py" 
    # update bucket name and script path in your bucket
  }
  
  default_arguments = {
    "--pip-install" = "pandas==1.3.3,numpy==1.21.2,scikit-learn==0.24.2,xgboost==1.4.2,boto3==1.18.12"
    # this is how you install extra libraries in ray
    # in case you need an extra one, you should pass the name and version here
  }
}

resource "aws_iam_role" "glue_role" {                   # the permission role starts here
  name = "glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_policy" "glue_s3_full_access_policy" {          
  name        = "GlueS3FullAccessPolicy"                            # don't change the name here
  description = "Policy to allow full access to S3 for Glue jobs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_s3_policy_attachment" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_s3_full_access_policy.arn
}

resource "aws_iam_role_policy_attachment" "glue_service_role_policy_attachment" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"    # and ends here
}