# typed: true
# frozen_string_literal: true

# Updates security and analysis settings for all repos in a business
class SecurityAnalysisSettingsUpdateBusinessJob < ApplicationJob
  queue_as :security_analysis_settings_business
  retry_on_dirty_exit

  LONG_RUNNING_SEQUENCE_HOURS = 1

  # Public: Updates security and analysis settings on all orgs within a business. This job will wait for all org enablement jobs to
  # finish before sending the BackfillGroupRequest.
  #
  # owner                       - The Business to perform security and analysis settings updates on.
  # update_type                 - The type of security and analysis settings being updated.
  # actor_id                    - ID of the actor that initiated the job
  # duration                    - How many seconds to wait for the job to check if all org jobs have finished.
  # enqueue_org_jobs            - Whether to enqueue org jobs or not. Usually set to false when already enqueued by a different process.
  # initially_enqueued_at       - The time the job was initially enqueued. Used to calculate entire job sequence timeout.
  # entity_type                 - The type of entity belonging to the enterprise to propagate the update to. :organization or :user
  def perform(owner, update_type, actor_id, duration: 15, enqueue_org_jobs: true, initially_enqueued_at: Time.current, entity_type: :organization)
    raise ArgumentError, "owner should be of type: Business" unless owner.is_a?(Business)

    actor = T.let(User.find(actor_id), User)

    GitHub.logger.with_named_tags(
      "enduser.id": actor.display_login,
      "gh.enduser.id": actor_id,
      "gh.enduser.login": actor.display_login,
      "gh.business.id": owner.id,
      "gh.business.name": owner.name,
      "gh.security_products.job.update_type": update_type,
      "gh.security_products.job.initial_start": initially_enqueued_at,
    ) do
      GitHub.logger.info("Job starting", "code.namespace": self.class.name, "code.function": __method__)

      if enqueue_org_jobs
        case entity_type
        when :organization
          find_and_enqueue_organizations(actor, owner, update_type)
        when :user
          find_and_enqueue_users(actor, owner, update_type)
        end
      end

      if Time.current >= initially_enqueued_at + LONG_RUNNING_SEQUENCE_HOURS.hours
        GitHub.logger.warn(
          "Jobs sequence has been running longer than #{LONG_RUNNING_SEQUENCE_HOURS} #{"hour".pluralize(LONG_RUNNING_SEQUENCE_HOURS)}",
          "code.namespace": self.class.name,
          "code.function": __method__,
        )
        GitHub.dogstats.increment("security_analysis_settings_update_business_job.long_running_sequence")
      end

      if BlockedSettings.new(owner).include?(update_type)
        GitHub.logger.info("Queuing next job to run after #{duration}-second delay", "code.namespace": self.class.name, "code.function": __method__)
        SecurityAnalysisSettingsUpdateBusinessJob
          .set(wait: duration.seconds)
          .perform_later(owner, update_type, actor_id, entity_type: entity_type, duration: duration, enqueue_org_jobs: false, initially_enqueued_at: initially_enqueued_at)
        GitHub.dogstats.increment("security_analysis_settings_update_business_job.schedule_next")
        return
      end

      backfill_request_allowed_update_types = [:secret_scanning_enable_all, :secret_scanning_disable_all]
      if backfill_request_allowed_update_types.include?(update_type)
        GitHub.logger.info("Sending backfill group request", "code.namespace": self.class.name, "code.function": __method__)
        GlobalInstrumenter.instrument("secret_scanning.backfill.group", {
          owner: owner,
          action: update_type == :secret_scanning_enable_all ? :START : :CANCEL,
          type: :FULL,
          requested_at: Time.now.utc,
          feature_flags: SecretScanning::Instrumentation::OwnerServiceFlags.new(owner).group_backfill_service_flags
        })
      end

      GitHub.dogstats.timing_since("security_analysis_settings_update_business_job.duration", initially_enqueued_at)

      GitHub.logger.info("Job finished", "code.namespace": self.class.name, "code.function": __method__)
    end
  end

  private

  def find_and_enqueue_organizations(actor, owner, update_type)
    enforce_policy_for_update_types = [:secret_scanning_enable_all, :advanced_security_enable_all]
    entities = owner.organizations
    entities = entities.filter(&:policy_allows_advanced_security_enablement?) if enforce_policy_for_update_types.include?(update_type)

    entities.each do |entity|
      enqueue_update_job(actor, entity, update_type)
    end
  end

  def find_and_enqueue_users(actor, owner, update_type)
    feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(owner)
    return unless feature.feature_available_for_user_repositories?

    current_page = 1
    entities = feature.list_enterprise_users_paged(page: current_page, per_page: 1000)

    while entities.length > 0
      entities.each do |entity|
        enqueue_update_job(actor, entity, update_type)
      end

      current_page += 1
      entities = feature.list_enterprise_users_paged(page: current_page, per_page: 1000)

      if current_page > 1000
        GitHub.logger.info("Paging enterprise users has surpassed 1000 pages")
        break
      end
    end
  end

  def enqueue_update_job(actor, entity, update_type)
    SecurityAnalysisSettingsUpdateJob.perform_later(
      actor: actor,
      emit_backfill_group_request: false,
      owner: entity,
      update_type: update_type,
    )
  end
end
