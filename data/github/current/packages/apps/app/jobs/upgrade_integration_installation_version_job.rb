# typed: strict
# frozen_string_literal: true

class UpgradeIntegrationInstallationVersionJob < ApplicationJob

  queue_as :upgrade_integration_installation_version

  exempt_from_tenant_context_requirement
  retry_on_dirty_exit

  BATCH_SIZE = 100
  FOUR_MINUTE_TIME_LIMIT = T.let(4.minutes, ActiveSupport::Duration)
  TWO_MINUTE_TIME_LIMIT = T.let(2.minutes, ActiveSupport::Duration)
  REMEDIATION_FEATURE_FLAG_NAME = :upgrade_integration_installation_version_retry_fix

  # This value represents the minimum installations count an app should have
  # in order to be considered "popular".
  #
  # This job emits app-specific tags based on apps popularity.
  MINIMIMUM_POPULAR_INSTALLATIONS_COUNT = 100_000

  sig { returns(T.nilable(Integration)) }
  attr_accessor :integration

  sig do
    params(
      integration_id: Integer,
      _: T.nilable(Integer),
      version_number: Integer,
      installation_id: T.nilable(Integer),
      outdated_version_number: T.nilable(Integer),
      updating_actor_id: T.nilable(Integer)
    ).void
  end
  def perform(integration_id, _, version_number, installation_id: nil, outdated_version_number: nil, updating_actor_id: nil)
    @integration = T.let(Integration.find(integration_id), T.nilable(Integration))

    # try read replica
    version = read_latest_version(T.must(integration), version_number, :reading)

    # try write master when not found
    version = version.nil? ? read_latest_version(T.must(integration), version_number, :writing) : version

    # if still not found drop it
    if version.nil?
      emit_count("drop_older_version")
      return
    end

    if installation_id.nil?
      emit_distribution("total_installations", installations_count(T.must(integration)), T.must(integration))
    end

    remediation_flag_enabled = T.must(integration).feature_flag_enabled?(REMEDIATION_FEATURE_FLAG_NAME, default: false)

    if outdated_version_number.nil?
      all_versions = T.must(integration).
        installations.
        select(:integration_version_number).
        distinct.
        order(:integration_version_number).
        pluck(:integration_version_number)

      # Don't bother running the job if all the installations are up to date.
      outdated_versions = all_versions.select { |number| number < version_number }
      return if outdated_versions.empty?

      if outdated_versions.any?
        if remediation_flag_enabled
          # Enqueue all but the most recent outdated version to be processed
          # in parallel.
          outdated_versions.each do |number|
            self.class.perform_later(
              integration_id,
              nil,
              version_number,
              outdated_version_number: number,
              installation_id: installation_id,
              updating_actor_id: updating_actor_id
            )
          end

          # If this job was enqueued without a specific outdated_version_number,
          # we only want to kick start the upgrade process.
          #
          # The jobs which include the outdated_version_number will do the actual work.
          #
          # This prevents duplicate specific jobs from being enqueued from this job in the
          # event of a failure happening during upgrades.
          #
          # Also, if there are no outdated versions, we have nothing to do.
          return
        else
          # Use this job to process the "latest" older version.
          outdated_version_number = outdated_versions.pop

          outdated_versions.each do |number|
            self.class.perform_later(
              integration_id,
              nil,
              version_number,
              outdated_version_number: number,
              installation_id: installation_id,
              updating_actor_id: updating_actor_id
            )
          end
        end
      end
    end

    time_out = remediation_flag_enabled ? TWO_MINUTE_TIME_LIMIT : FOUR_MINUTE_TIME_LIMIT
    GitHub::SafeTimer.timeout(time_out) do |timer|
      batch_options = { batch_size: BATCH_SIZE }
      batch_options[:start] = installation_id unless installation_id.nil?

      scope = T.must(integration).installations.where(integration_version_number: outdated_version_number).includes(:target)

      scope.find_in_batches(**batch_options) do |installations|
        # This job can take a long time for Apps with many thousands of
        # installations. To avoid the job queue system killing this in the
        # middle of upgrading, we want to enqueue the job again after some
        # time.
        unless timer.run?
          self.class.perform_later(
            integration_id, nil, version_number,
            installation_id: installations.first&.id,
            outdated_version_number: outdated_version_number,
            updating_actor_id: updating_actor_id
          )

          emit_count("timed_out")
          return
        end

        if cancel_upgrade?(T.must(integration))
          emit_count("cancelled")
          return
        end

        process_batch(T.must(integration), installations, version, updating_actor_id, remediation_flag_enabled: remediation_flag_enabled)
      end

      emit_count("finished")
    end
  end

  private

  sig { params(integration: Integration, installations: T::Array[IntegrationInstallation], version: IntegrationVersion, updating_actor_id: T.nilable(Integer), remediation_flag_enabled: T::Boolean).void }
  def process_batch(integration, installations, version, updating_actor_id = nil, remediation_flag_enabled:)
    initial_time = Time.now

    upgrade_installation_version(installations, version, updating_actor_id, remediation_flag_enabled: remediation_flag_enabled)

    emit_distribution("updated_installations", installations.count, integration)

    elapsed_time_in_seconds  = [1, (Time.now - initial_time).to_i].max
    installations_per_second = (installations.count / elapsed_time_in_seconds).to_i

    emit_distribution("installations_per_second", installations_per_second, integration)
  end

  sig { params(installations: T::Array[IntegrationInstallation], version: IntegrationVersion, updating_actor_id: T.nilable(Integer), remediation_flag_enabled: T::Boolean).void }
  def upgrade_installation_version(installations, version, updating_actor_id = nil, remediation_flag_enabled:)
    IntegrationInstallation.throttle do
      installations.each do |installation|
        with_active_record_error_retry do
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

          if remediation_flag_enabled && installation_up_to_date?(installation, version.number)
            emit_count("skip_up_to_date_installation")
            next
          end

          result = ActiveRecord::Base.connected_to(role: :writing) do
            installation.auto_update_version(editor: editor, version: version, entry_point: :upgrade_integration_installation_version_job_auto_upgrade, updating_actor_id: updating_actor_id)
          end
          next if result.success?

          if result.cannot_auto_upgrade?
            DeliverIntegrationUpdateEmailJob.perform_later(installation.id, integration_version_id: version.id)
          else
            Failbot.report(result.error)
          end
        end
      end
    end
  end

  sig { returns(T::Array[String]) }
  def tags_for_integration
    return T.must(@tags_for_integration) if defined?(@tags_for_integration)

    popular = popular_integration?(T.must(integration))
    @tags_for_integration = T.let(["popular:#{popular}"], T.nilable(T::Array[String]))

    return T.must(@tags_for_integration) unless popular

    T.must(@tags_for_integration) << "integration:#{T.must(integration).slug}"

    T.must(@tags_for_integration)
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
      tags: tags_for_integration,
    )
  end

  sig { params(suffix: String).void }
  def emit_count(suffix)
    GitHub.dogstats.count(
      "job.upgrade_integration_installation_version_job.#{suffix}",
      1,
      tags: tags_for_integration,
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
    FeatureFlag.vexi.enabled?(:cancel_upgrade_integration_installation_version_job, integration, default: false)
  end

  sig { params(installation: IntegrationInstallation, version_number: Integer).returns(T::Boolean) }
  def installation_up_to_date?(installation, version_number)
    IntegrationInstallation.select(:integration_version_number).where(id: installation.id, integration_version_number: version_number).exists?
  end

  sig { params(integration: Integration, version_number: Integer, role: Symbol).returns(T.nilable(IntegrationVersion)) }
  def read_latest_version(integration, version_number, role)
    ActiveRecord::Base.connected_to(role: role) do
      v = integration.versions.reorder(id: :desc).first
      v&.number == version_number ? v : nil
    end
  end

  # Private: Retry once on errors caused by ActiveRecordErrors.
  #
  # The wrapper fails open and logs inner exceptions, making it suitable for batch processing.
  sig { params(stats_prefix: String, block: T.proc.void).void }
  def with_active_record_error_retry(stats_prefix: "", &block)
    retried = T.let(false, T::Boolean)
    stats_prefix = "#{stats_prefix}." unless stats_prefix.empty?
    begin
      block.call
    rescue ActiveRecord::ActiveRecordError => e
      if retried
        emit_count("#{stats_prefix}failed_retry")
        log("failed_retry", T.must(integration), e.to_s)
        Failbot.report!(e)
        return
      end

      emit_count("#{stats_prefix}retry")
      log("retry", T.must(integration), e.to_s)
      retried = true
      retry
    end
  end
end
