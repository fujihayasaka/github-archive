# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  # Service object responsible for upgrading a single IntegrationInstallation
  # to a target IntegrationVersion.
  class VersionUpgrade
    class CannotAutoUpgradeError < StandardError; end

    include GitHub::Memoizer

    # Upgrade a single installation to the target version.
    sig do
      params(
        installation: IntegrationInstallation,
        integration: Integration,
        target_version: IntegrationVersion,
        updating_actor_id: T.nilable(Integer),
        popular: T::Boolean
      ).void
    end
    def self.call(installation:, integration:, target_version:, updating_actor_id: nil, popular: false)
      new(
        installation: installation,
        integration: integration,
        target_version: target_version,
        updating_actor_id: updating_actor_id,
        popular: popular,
      ).call
    end

    sig do
      params(
        installation: IntegrationInstallation,
        integration: Integration,
        target_version: IntegrationVersion,
        updating_actor_id: T.nilable(Integer),
        popular: T::Boolean
      ).void
    end
    def initialize(installation:, integration:, target_version:, updating_actor_id: nil, popular: false)
      @installation = installation
      @integration = integration
      @target_version = target_version
      @updating_actor_id = updating_actor_id
      @popular = popular
    end

    def call
      with_active_record_error_retry { perform_upgrade }
    end

    private

    attr_reader :installation, :integration, :target_version, :updating_actor_id, :popular

    def perform_upgrade
      return emit_installation_skipped if installation_up_to_date?
      return report_missing_editor     if editor.blank?

      upgrade_or_request_manual_approval
    end

    def upgrade_or_request_manual_approval
      result = perform_auto_upgrade
      if result.success?
        emit_count("upgrade_success")
        return
      end
      return request_manual_approval if result.cannot_auto_upgrade?

      emit_count("upgrade_unexpected_error")
      Failbot.report(CannotAutoUpgradeError.new(result.error))
    end

    def perform_auto_upgrade
      ActiveRecord::Base.connected_to(role: :writing) do
        installation.auto_update_version(
          editor: editor,
          version: target_version,
          entry_point: :upgrade_integration_installation_version_job_auto_upgrade,
          updating_actor_id: updating_actor_id,
        )
      end
    end

    def request_manual_approval
      emit_count("manual_approval_requested")
      DeliverIntegrationUpdateEmailJob.perform_later(installation.id, integration_version_id: target_version.id)
    end

    def installation_up_to_date?
      IntegrationInstallation
        .select(:integration_version_number)
        .where(id: installation.id, integration_version_number: target_version.number)
        .exists?
    end

    def emit_installation_skipped
      emit_count("skip_up_to_date_installation")
    end

    memoize def editor
      if installation.target.is_a?(::Business)
        User.find_by(id: GitHub.context[:actor_id])
      else
        installation.target
      end
    end

    def report_missing_editor
      emit_count("missing_editor")
      error = RuntimeError.new("No permissions editor found for installation with ID #{installation.id}")
      Failbot.report(error)
    end

    # Retry once on transient ActiveRecord errors (e.g. lock timeouts).
    # Fails open: logs and reports on second failure, does not re-raise.
    def with_active_record_error_retry(&block)
      retried = T.let(false, T::Boolean)
      begin
        block.call
      rescue ActiveRecord::ActiveRecordError => e
        if retried
          emit_transient_retry_failed(e)
          Failbot.report!(e)
          return
        end

        emit_transient_retry(e)
        retried = true
        retry
      end
    end

    def emit_transient_retry(e)
      emit_count("retry")
      log_error("retry", e)
    end

    def emit_transient_retry_failed(e)
      emit_count("failed_retry")
      log_error("failed_retry", e)
    end

    def emit_count(suffix)
      GitHub.dogstats.count(
        "job.upgrade_integration_installation_version_batched_job.#{suffix}",
        1,
        tags: tags_for_integration,
      )
    end

    def log_error(action, exception)
      GitHub.logger.info(
        "gh.job.name" => self.class.name,
        "gh.job.action" => action,
        "gh.integration.id" => integration.id,
        "gh.job.exception_message" => exception.to_s,
      )
    end

    memoize def tags_for_integration
      tags = ["popular:#{popular}"]
      tags << "integration:#{integration.slug}" if popular
      tags
    end
  end
end
