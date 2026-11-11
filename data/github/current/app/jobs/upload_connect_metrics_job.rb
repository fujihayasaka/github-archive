# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UploadConnectMetricsJob < ApplicationJob
  queue_as :github_connect
  retry_on_dirty_exit

  # Make sure we this job only runs in GHES.
  schedule interval: 1.day, condition: -> { GitHub.enterprise? }

  # https://thehub.github.com/engineering/development-and-ops/dotcom/background-jobs/lockable-jobs/
  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  retry_on GitHub::Connect::Authenticator::ConnectionError,
    wait: :polynomially_longer,
    attempts: 3

  retry_on GitHub::Connect::ApiError,
    wait: :polynomially_longer,
    attempts: 3

  def perform
    return unless GitHub.dotcom_connection_enabled? && GitHub.ghe_usage_metrics_enabled?

    dotcom_connection = DotcomConnection.new

    res = with_write { dotcom_connection.upload_connect_metrics }
    raise GitHub::Connect::ApiError.new("error sending GitHub Connect metrics") unless res[:failures].empty?
  end
end
