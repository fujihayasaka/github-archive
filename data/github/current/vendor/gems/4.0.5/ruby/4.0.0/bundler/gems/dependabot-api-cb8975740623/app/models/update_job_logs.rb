# frozen_string_literal: true

class UpdateJobLogs
  SENSITIVE_INFO_FILTERS = [
    /githubapp.com/,
  ].freeze

  # Dependabot update job log retention in AWS S3 (Deltaforce Production)
  # Update the following references when changing the retention:
  # https://github.com/github/github/blob/master/app%2Fmodels%2Frepository_dependency_update.rb#L25
  # https://github.com/github/composer/blob/4b0629994d4d753b404479510f161819c970710c/sites/dfprod-us-east-1/main.tf#L42
  DEPENDABOT_UPDATE_JOB_LOG_RETENTION_DAYS = 14

  attr_reader :update_job

  def initialize(update_job)
    @update_job = update_job
  end

  def user_readable
    s3_events.split("\n").each_with_object([]) do |line, lines|
      next if sensitive?(line)

      lines << line
    end.join("\n")
  end

  def staff_readable
    s3_events
  end

  private

  def s3_client
    return @s3_client if defined?(@s3_client)

    @s3_client = Aws::S3::Client.new
  end

  def s3_bucket
    Prius.get(:update_job_log_bucket)
  end

  def s3_events
    return "" if update_job.actions?

    cache_key = "update_job_logs/s3/#{update_job.id}"
    Rails.cache.fetch(cache_key, expires_in: 2.hours) do
      data = s3_client.get_object(
        bucket: s3_bucket,
        key: "job-#{update_job.id}"
      ).body.read

      unzip(data)
    end
  rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::AccessDenied
    ""
  end

  def unzip(data)
    reader = Zlib::GzipReader.new(StringIO.new(data))
    logs = reader.read
    reader.close
    logs
  end

  # Some calls expose our internal APIs or other information which could be
  # abused by a malicious actor, so we filter by default.
  def sensitive?(message)
    SENSITIVE_INFO_FILTERS.any? { |filter| message.match?(filter) }
  end
end
