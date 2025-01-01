# typed: true
# frozen_string_literal: true

require "github/turboscan_uploaders/i_uploader"

module GitHub
  module TurboscanUploaders
    # TurboscanUploaders::S3 is responsible for uploading files to S3
    class S3
      include GitHub::TurboscanUploaders::IUploader

      def initialize(client = nil)
        @client = client
      end

      def client
        @client ||= GitHub.s3_turboscan_client
      end

      sig { override.params(sarif: String, target: String, c: T.nilable(Aws::S3::Client)).returns(String) }
      def upload(sarif, target, c = client)
        GitHub.dogstats.distribution("turboscan_client.s3_file_size", sarif.size)
        GitHub.dogstats.distribution_time("turboscan_client.s3_upload") do
          bucket = GitHub.turboscan_s3_bucket
          client.put_object(
            body: sarif,
            bucket: bucket,
            key: target,
            server_side_encryption: GitHub.s3_turboscan_sse? ? "aws:kms" : nil,
          )
        end
        target
      end
    end
  end
end
