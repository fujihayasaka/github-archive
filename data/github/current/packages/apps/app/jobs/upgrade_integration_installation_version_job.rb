# typed: strict
# frozen_string_literal: true

class UpgradeIntegrationInstallationVersionJob < ApplicationJob

  queue_as :upgrade_integration_installation_version

  exempt_from_tenant_context_requirement
  retry_on_dirty_exit

  BATCH_SIZE = 100
  TIME_LIMIT = T.let(4.minutes, ActiveSupport::Duration)

  # This value represents the minimum installations count an app should have
  # in order to be considered "popular".
  #
  # This job emits app-specific tags based on apps popularity.
  MINIMIMUM_POPULAR_INSTALLATIONS_COUNT = 100_000

  sig do
    params(
      integration_id: Integer,
      _: T.nilable(Integer),
      version_number: Integer,
      installation_id: T.nilable(Integer),
      outdated_version_number: T.nilable(Integer)
    ).void
  end
  def perform(integration_id, _, version_number, installation_id: nil, outdated_version_number: nil)
    integration = Integration.find(integration_id)

    # try read replica
    version = read_latest_version(integration, version_number, :reading)

    # try write master when not found
    version = version.nil? ? read_latest_version(integration, version_number, :writing) : version

    # if still not found drop it
    if version.nil?
      emit_count("drop_older_version", integration)
      return
    end

    if installation_id.nil?
      emit_distribution("total_installations", installations_count(integration), integration)
    end

    if outdated_version_number.nil?
      all_versions = integration.
        installations.
        select(:integration_version_number).
        distinct.
        order(:integration_version_number).
        pluck(:integration_version_number)

      # Don't bother running the job if all the installations are up to date.
      outdated_versions = all_versions.select { |number| number < version_number }
      return if outdated_versions.empty?

      # Use this job to process the "latest" older version.
      outdated_version_number = outdated_versions.pop

      if outdated_versions.any?
        # Enqueue all but the most recent outdated version to be processed
        # in parallel.
        outdated_versions.each do |number|
          self.class.perform_later(integration_id, nil, version_number, outdated_version_number: number)
        end
      end
    end

    GitHub::SafeTimer.timeout(TIME_LIMIT) do |timer|
      batch_options = { batch_size: BATCH_SIZE }
      batch_options[:start] = installation_id unless installation_id.nil?

      scope = integration.installations.where(integration_version_number: outdated_version_number).includes(:target)

      scope.find_in_batches(**batch_options) do |installations|
        # This job can take a long time for Apps with many thousands of
        # installations. To avoid the job queue system killing this in the
        # middle of upgrading, we want to enqueue the job again after some
        # time.
        unless timer.run?
          self.class.perform_later(
            integration_id, nil, version_number,
            installation_id: installations.first&.id,
            outdated_version_number: outdated_version_number
          )

          emit_count("timed_out", integration)
          return
        end

        if cancel_upgrade?(integration)
          emit_count("cancelled", integration)
          return
        end

        with_active_record_error_retry(integration, stats_prefix: "process_batch") do
          process_batch(integration, installations, version)
        end
      end

      emit_count("finished", integration)
    end
  end

  private

  sig { params(integration: Integration, installations: T::Array[IntegrationInstallation], version: IntegrationVersion).void }
  def process_batch(integration, installations, version)
    initial_time = Time.now

    ActiveRecord::Base.connected_to(role: :writing) do
      upgrade_installation_version(installations, version)
    end

    emit_distribution("updated_installations", installations.count, integration)

    elapsed_time_in_seconds  = [1, (Time.now - initial_time).to_i].max
    installations_per_second = (installations.count / elapsed_time_in_seconds).to_i

    emit_distribution("installations_per_second", installations_per_second, integration)
  end

  sig { params(installations: T::Array[IntegrationInstallation], version: IntegrationVersion).void }
  def upgrade_installation_version(installations, version)
    IntegrationInstallation.throttle do
      installations.each do |installation|
        editor =
          if installation.target.is_a?(::Business)
            User.find_by(id: GitHub.context[:actor_id])
          else
            installation.target
          end

        unless editor
          boom = RuntimeError.new "No permissions editor found for installation with ID #{installation.id}"
          Failbot.report boom
          next
        end

        result = installation.auto_update_version(editor: editor, version: version, entry_point: :upgrade_integration_installation_version_job_auto_upgrade)
        next if result.success?

        if result.cannot_auto_upgrade?
          DeliverIntegrationUpdateEmailJob.perform_later(installation.id, integration_version_id: version.id)
        else
          Failbot.report(result.error)
        end
      end
    end
  end

  sig { params(integration: Integration).returns(T::Array[String]) }
  def build_tags_for(integration)
    popular = popular_integration?(integration)
    tags = ["popular:#{popular}"]
    return tags unless popular

    tags.append("integration:#{integration.slug}")
  end

  sig { params(integration: Integration).returns(T::Boolean) }
  def popular_integration?(integration)
    installations_count(integration) > MINIMIMUM_POPULAR_INSTALLATIONS_COUNT
  end

  sig { params(integration: Integration).returns(Integer) }
  def installations_count(integration)
    @total_installations_count ||= T.let(integration.installations.count, T.untyped)
  end

  sig { params(suffix: String, value: Integer, integration: Integration).void }
  def emit_distribution(suffix, value, integration)
    GitHub.dogstats.distribution(
      "job.upgrade_integration_installation_version_job.#{suffix}",
      value,
      tags: build_tags_for(integration),
    )
  end

  sig { params(suffix: String, integration: Integration).void }
  def emit_count(suffix, integration)
    GitHub.dogstats.count(
      "job.upgrade_integration_installation_version_job.#{suffix}",
      1,
      tags: build_tags_for(integration),
    )
  end

  sig { params(action: String, integration: Integration, exception: String).void }
  def log(action, integration, exception)
    GitHub.logger.info(
      "gh.job.name" => self.class.name,
      "gh.job.action" => action,
      "gh.integration.id" => integration.id,
      "gh.job.exception_message" => exception
    )
  end

  sig { params(integration: Integration).returns(T::Boolean) }
  def cancel_upgrade?(integration)
    GitHub.flipper[:cancel_upgrade_integration_installation_version_job].enabled?(integration)
  end

  sig { params(integration: Integration, version_number: Integer, role: Symbol).returns(T.nilable(IntegrationVersion)) }
  def read_latest_version(integration, version_number, role)
    version = ActiveRecord::Base.connected_to(role: role) do
      v = integration.versions.reorder(id: :desc).first
      v&.number == version_number ? v : nil
    end
  end

  # Private: Retry once on errors caused by ActiveRecordErrors.
  #
  # The wrapper fails open and logs inner exceptions, making it suitable for batch processing.
  sig { params(integration: Integration, stats_prefix: String, block: T.proc.void).void }
  def with_active_record_error_retry(integration, stats_prefix:, &block)
    retried = T.let(false, T::Boolean)
    begin
      block.call
    rescue ActiveRecord::ActiveRecordError => e
      if retried
        emit_count("#{stats_prefix}.failed_retry", integration)
        log("failed_retry", integration, e.to_s)
        Failbot.report!(e)
        return
      end

      emit_count("#{stats_prefix}.retry", integration)
      log("retry", integration, e.to_s)
      retried = true
      retry
    end
  end
end
