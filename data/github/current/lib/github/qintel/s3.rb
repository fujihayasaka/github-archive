# typed: true
# frozen_string_literal: true

module GitHub
  module Qintel
    class S3
      BUCKET = "github-compromised-credential-files"

      def self.upload(uuid:, file:)
        GitHub.s3_compromised_credential_files_client.put_object({
          key: uuid,
          bucket: BUCKET,
          body: file,
        })
      end

      def self.download(uuid:, file:)
        GitHub.s3_compromised_credential_files_client.get_object({
          bucket: BUCKET,
          key: uuid,
          response_target: file.path,
        })
      end

      def self.exists?(uuid:)
        begin
          GitHub.s3_compromised_credential_files_client.head_object({
            bucket: BUCKET,
            key: uuid,
          })
          true
        rescue Aws::S3::Errors::NotFound
          false
        end
      end
    end
  end
end
