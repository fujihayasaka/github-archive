# typed: false
# frozen_string_literal: true

module Storage
  module Uploadable
    module S3Policy
      extend ActiveSupport::Concern

      class_methods do
        def storage_s3_hostname
          "#{storage_s3_bucket}.s3.amazonaws.com"
        end

        def storage_s3_new_bucket_host
          "#{storage_s3_new_bucket}.s3.amazonaws.com"
        end
      end

      def storage_s3_key(policy)
        Storage.not_implemented!(policy, self, :storage_s3_key)
      end

      def storage_s3_download_query(q)
      end

      def storage_s3_access
        :private
      end

      def storage_s3_region
        "us-east-1"
      end

      def storage_supports_multi_part_upload
        true
      end

      def storage_s3_upload_header
        {
          "Content-Type" => content_type,
        }
      end

      def storage_download_expiration
        5.minutes
      end

      def storage_upload_expiration
        30.minutes
      end

      def storage_s3_access_key
        GitHub.s3_environment_config[:access_key_id]
      end

      def storage_s3_secret_key
        GitHub.s3_environment_config[:secret_access_key]
      end

      def storage_s3_bucket
        GitHub.s3_environment_config[:asset_bucket_name]
      end

      def storage_fastly_acceleration_bucket(repository)
        # Not configured by default
      end

      class RetryError < StandardError
        attr_reader :record_ids
        def initialize(record_ids, *args)
          @record_ids = Array(record_ids).map(&:to_i).select { |id| id > 0 }
          super(*args)
        end
      end
    end
  end
end
