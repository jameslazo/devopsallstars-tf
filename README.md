# Terraform Repo for #DevOpsAllStarsChallenge Projects
This repo contains the main.tf and vars.tf HCL used to provision all AWS resources in my #DevOpsAllStarsChallenge projects. <Insert link to overview repo.>
## Resources
### All Projects
- AWS Provider
- VPC
- IAM Role|Policy|Policy Attachment for GitHubs Actions
- S3 Bucket for Lambda deployments

### Day 1: [Upload Weather API Data](https://github.com/jameslazo/devopsallstars-day01-weather) | [Medium](https://medium.com/@james.lazo/day-1-devops-challenge-2edfd73ac9b6)
- S3 Bucket for weather data

### Day 2: [Scheduled SNS Notification with API Data](https://github.com/jameslazo/devopsallstars-day02-notification) | [Medium](https://medium.com/@james.lazo/day-2-devops-challenge-3e7038fd3f58)
- Lambda Function
- SNS Topic
- CloudWatch EventBridge Rule|Target|Invocation
- IAM Roles|Policies|Policy Attachments

### Day 3: [Data Lake Pipeline](https://github.com/jameslazo/devopsallstars-day03-datalake) | [Medium](https://medium.com/@james.lazo/day-3-devops-challenge-data-lake-e666aef6361e)
- Lambda Functions (API|Extraction)
- S3 Buckets (Raw|Extracted|Athena)
- Glue Catalog Database
- Glue Catalog Table
- Glue Crawler
- Athena Workgroup
- IAM Roles|Policies|Policy Attachments
