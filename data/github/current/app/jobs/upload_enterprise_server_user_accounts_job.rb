# typed: true
# frozen_string_literal: true

# Uploads user account information to GitHub Enterprise Cloud.
#
# Expects no arguments, as the data to be sent will be generated while the job
# runs.
class UploadEnterpriseServerUserAccountsJob < ApplicationJob
  SCHEDULE_INTERVAL = 1.week

  queue_as :github_connect

  attr_reader :accounts_data, :status

  schedule interval: SCHEDULE_INTERVAL, condition: -> { GitHub.enterprise? }

  def self.human_readable_schedule_interval
    "weekly" if SCHEDULE_INTERVAL == 1.week
  end

  def self.job_id
    "upload-enterprise-server-user-accounts"
  end

  def self.status
    JobStatus.find(UploadEnterpriseServerUserAccountsJob.job_id)
  end

  def self.status!
    JobStatus.find!(UploadEnterpriseServerUserAccountsJob.job_id)
  end

  def perform
    return unless GitHub.dotcom_user_license_usage_upload_enabled?
    return unless dotcom_connection.authentication_token?

    with_write do
      @status = get_status
      status.track do
        dotcom_connection.upload_license_info
      end
    end
  end

  def dotcom_connection
    @dotcom_connection ||= DotcomConnection.new
  end

  def get_status
    UploadEnterpriseServerUserAccountsJob.status ||
      JobStatus.create(id: UploadEnterpriseServerUserAccountsJob.job_id)
  end
end
