# frozen_string_literal: true

require "aws-sdk-s3"

credentials = Aws::Credentials.new(
  Prius.get(:aws_access_key_id),
  Prius.get(:aws_secret_access_key),
)

Aws.config.update(region: Prius.get(:aws_region), credentials: credentials)

if Dependabot.enterprise?
  Aws.config.update(
    endpoint: Prius.get(:aws_endpoint),
  )
  Aws.config[:s3] = { force_path_style: true }
end
