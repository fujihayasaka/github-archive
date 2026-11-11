# typed: strict
# frozen_string_literal: true

# Resyncs Copilot policy settings to organizations for every Business (enterprise)
# that has at least one setting rule configured for a propagatable Copilot model
# policy.
#
# For each (business_id, feature) pair where `feature` is a propagatable policy
# config_name that the business has a rule for, this job enqueues a
# `Copilot::NewBatchUpdateOrgSettingsJob` to re-propagate the business value to
# its child organizations.
#
# Runs regardless of the rollout feature flag state — the use case is
# "we turned the flag off and need to catch organizations back up."
class Copilot::BatchUpdateAllEnterpriseOrgSettingsJob < CopilotJob
  queue_as :copilot_batch_update_all_enterprise_org_settings
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  # This job is a global operation and is not scoped to a single tenant. Per-tenant
  # work happens in the `NewBatchUpdateOrgSettingsJob` instances it enqueues.
  exempt_from_tenant_context_requirement

  # Number of `copilot_settings` rows to load per batch when scanning for rules.
  SETTINGS_BATCH_SIZE = T.let(100, Integer)

  # Number of (business_id, feature) pairs to enqueue per `wait` slice.
  # Each slice fires `SPREAD_SECONDS` later than the previous one, so child
  # jobs do not all hit the queue at the same instant.
  ENQUEUE_BATCH_SIZE = T.let(50, Integer)

  # Seconds to add to the `wait:` offset for each successive slice of
  # `ENQUEUE_BATCH_SIZE` enqueued child jobs.
  SPREAD_SECONDS = T.let(10, Integer)

  sig { void }
  def perform
    GitHub.logger.info(
      "info.message" => "Starting copilot batch_update_all_enterprise_org_settings_job",
    )

    propagatable_features = T.let(
      Copilot::Policies::PROPAGATABLE
        .select(&:setting_rules_supported_policy?)
        .map { |p| p.config_name.to_sym },
      T::Array[Symbol]
    ).to_set

    if propagatable_features.empty?
      GitHub.logger.info(
        "info.message" => "No propagatable Copilot policies support setting rules; nothing to resync",
      )
      return
    end

    business_rules = find_business_rules(propagatable_features)

    enqueue_jobs(business_rules)
  end

  private

  # Find every distinct (business_id, feature) pair that has a rule for a
  # propagatable model policy.
  sig { params(propagatable_features: T::Set[Symbol]).returns(T::Array[[Integer, Symbol]]) }
  def find_business_rules(propagatable_features)
    business_rules = T.let(Set.new, T::Set[[Integer, Symbol]])

    Copilot::Settings::Setting
      .where(resource_type: "Business", name: Copilot::Settings::CopilotModelsGroup::NAME)
      .includes(:rules)
      .find_each(batch_size: SETTINGS_BATCH_SIZE) do |setting|
        business_id = setting.resource_id

        setting.rules.each do |rule|
          values = rule.parameters.is_a?(Hash) ? rule.parameters["values"] : nil
          next unless values.is_a?(Hash)

          values.each_key do |model_name|
            feature = model_name.to_sym
            next unless propagatable_features.include?(feature)

            business_rules << [business_id, feature]
          end
        end
      end

    business_rules.to_a
  end

  sig { params(business_rules: T::Array[[Integer, Symbol]]).void }
  def enqueue_jobs(business_rules)
    distinct_business_ids = business_rules.map(&:first).uniq.size
    enqueued_count = 0

    business_rules.each_slice(ENQUEUE_BATCH_SIZE).with_index do |slice, slice_index|
      wait_seconds = slice_index * SPREAD_SECONDS

      slice.each do |business_id, feature|
        job = Copilot::NewBatchUpdateOrgSettingsJob
        job = job.set(wait: wait_seconds.seconds) if wait_seconds.positive?
        job.perform_later(business_id, feature)
        enqueued_count += 1
      end
    end

    GitHub.logger.info(
      "info.message" => "Finished copilot batch_update_all_enterprise_org_settings_job",
      "copilot.businesses_count" => distinct_business_ids,
      "copilot.business_rules_count" => business_rules.size,
      "copilot.enqueued_count" => enqueued_count,
    )
  end
end
