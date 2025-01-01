# typed: true
# frozen_string_literal: true

require "s3_sign"

module Octoshift
  module Service
    class LogStorageHelper
      class UploadError < StandardError; end
      class GenerateUrlError < StandardError; end
      class MissingCredentialsError < StandardError; end

      SIGNED_URL_EXPIRATION_TIME = 5.days
      LOGS_EXTENSION = "-logs.txt"

      def upload_repo_log(org_name, log_name, content)
        org_logs_path = Dir.mktmpdir(org_name)
        repository_key = File.join(org_name, "#{log_name}#{LOGS_EXTENSION}")
        repository_log_file_path = File.join(org_logs_path, "#{log_name}#{LOGS_EXTENSION}")
        File.open(repository_log_file_path, "wb") do |file|
          file.write(content)
          file.close
          upload(repository_key, file)
        end
      rescue Aws::S3::Errors::ServiceError
        raise(UploadError, "Failed to upload migration log for: #{log_name}")
      rescue Aws::Sigv4::Errors::MissingCredentialsError
        raise(MissingCredentialsError, "Could not connect to Azure: Missing Credentials. Could not upload logs for: #{log_name}")
      ensure
        FileUtils.remove_entry(org_logs_path) if !org_logs_path.nil? && File.exist?(org_logs_path)
      end

      def get_repo_log_url(org_name, log_name)
        repo_key = "#{org_name}/#{log_name}#{LOGS_EXTENSION}"
        memory_alpha_client.get_object({
          bucket: GitHub.octoshift_memory_alpha_bucket,
          key: repo_key
        })
        signed_url_for(repo_key)
      rescue Aws::S3::Errors::NotFound
        raise(GenerateUrlError, "Failed to generate url to download migration log for: #{log_name}")
      end

      private

      # Returns an S3 client for Memory-Alpha for Octoshift's Azure container.
      # This account stores objects for internal services.
      def memory_alpha_client
        @memory_alpha_client ||= Aws::S3::Client.new({
          endpoint: GitHub.memory_alpha_url,
          force_path_style: true,
          access_key_id: GitHub.octoshift_memory_alpha_key_id,
          secret_access_key: GitHub.octoshift_memory_alpha_access_key,
          region: "us-west-2"
        })
      end

      # Uploads content to a designated path (key) using Memory Alpha.
      def upload(key, content)
        memory_alpha_client.put_object(
          body: content,
          bucket: GitHub.octoshift_memory_alpha_bucket,
          key: key,
        )
      end

      # Uploads and returns a signed url for an uploaded object.
      def signed_url_for(key)
        s3_credentials = {
          bucket: GitHub.octoshift_memory_alpha_bucket,
          key: GitHub.octoshift_memory_alpha_key_id,
          secret: GitHub.octoshift_memory_alpha_access_key,
        }

        MemoryAlphaSign.query(s3_credentials, "GET", key, SIGNED_URL_EXPIRATION_TIME).location
      end
    end
  end
end
