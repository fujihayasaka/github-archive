# typed: strict
# frozen_string_literal: true

module Hook::ActionsDependency
  extend T::Helpers

  requires_ancestor { Hook::DeliverySystem }

  # Degrade Actions gracefully during an incident by dropping webhooks that are 30+ minutes old
  ACTIONS_AQUEDUCT_JOB_TTL = T.let(30 * 60, Integer)

  sig { params(parent: String).returns(T::Boolean) }
  def self.is_actions_delivery?(parent)
    is_actions_prod_delivery?(parent) || is_actions_lab_delivery?(parent)
  end

  sig { params(parent: String).returns(T::Boolean) }
  def self.is_actions_prod_delivery?(parent)
    parent == "integration-#{GitHub.launch_github_app&.id}"
  end

  sig { params(parent: String).returns(T::Boolean) }
  def self.is_actions_lab_delivery?(parent)
    parent == "integration-#{GitHub.launch_lab_github_app&.id}"
  end

  sig { params(parent: String).returns(String) }
  def self.actions_queue_for(parent)
    return "webhooks-lab" if is_actions_lab_delivery?(parent)

    "webhooks"
  end

  sig { params(job_args: T::Hash[T.untyped, T.untyped], payload: T::Hash[T.untyped, T.untyped], queue: String).void }
  def self.add_ttl_to_aqueduct_job_args(job_args, payload, queue)
    if !GitHub.enterprise?
      hook_triggered_at = SimpleUUID::UUID.new(payload[:guid]).to_time
      hook_age = get_actions_hook_age(hook_triggered_at)
      ttl_seconds = get_actions_hook_ttl(hook_age)
      job_args[:ttl] = ttl_seconds
      # Jobs queued with a TTL of 0 will be immediately marked as expired by Aqueduct and not delivered
      if ttl_seconds == 0
        log_expired_actions_hook(queue, payload, hook_triggered_at, hook_age)
      end
    end
  end

  sig { returns T::Boolean }
  def is_filterable_actions_triggered_event?
    return false unless hook_event.target_repository

    event_type = hook_event.event_type

    return false if event_type == "workflow_dispatch" || event_type == "repository_dispatch"

    # When a workflow run is triggered by the Actions bot, we don't want to filter it out
    if GitHub.flipper[:workflow_run_is_not_filtered].enabled?(hook_event.target_repository)
      return false if event_type == "workflow_run"
    end

    # Launch relies on push events to sync scheduled workflows, so we shouldn't filter these out
    return false if event_type == "push"

    # Rerequested check suites are used for re-runs and should not be filtered out
    return false if event_type == "check_suite" && hook_event.try(:action) && hook_event.action.to_sym == :rerequested

    ActiveRecord::Base.connected_to(role: :reading) do
      return false unless GitHub.actions_enabled? && GitHub.launch_github_app

      if event_type == "check_suite" || event_type == "check_run"
        return true if hook_event.app.id == GitHub.launch_github_app.id
      end

      begin
        actor = hook_event.actor
      rescue NotImplementedError
        return false
      end

      return false unless actor

      actor == GitHub.launch_github_app.bot
    end
  end

  sig { returns T::Boolean }
  def require_on_demand_actions_app_installation?
    return false unless hook_event.target_repository
    return false unless hook_event.event_type.in?(%w[pull_request merge_group])

    target_repo = hook_event.target_repository
    return false if !GitHub.enterprise? && !GitHub.flipper[:actions_required_workflows_on_demand_app_installation].enabled?(target_repo.owner)

    record_on_demand_actions_app_installation_check_duration do
      ActiveRecord::Base.connected_to(role: :reading) do
        return false if target_repo.actions_app_installed?

        # We want to enable actions app on a repo
        # only if ruleset workflows are configured to run on it.
        has_ruleset_workflows = RulesEngine::WorkflowsHelper.enabled_workflow_rule_for_repo?(target_repo)
        return false if !has_ruleset_workflows
      end
    end

    true
  end

  sig { params(blk: T.proc.returns(T::Boolean)).void }
  def record_on_demand_actions_app_installation_check_duration(&blk)
    start_time = GitHub::Dogstats.monotonic_time
    yield
  ensure
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("actions.require_on_demand_actions_app_installation", elapsed)

    GitHub::logger.info("time taken to require_on_demand_actions_app_installation", {
      "gh.request_id" => GitHub.context[:request_id],
      "code.namespace" => "Hook::DeliverySystem",
      "code.function" => "require_on_demand_actions_app_installation",
      "gh.catalog_service" => "github/actions_experience",
      "gh.webhook.delivery_guid" => hook_event.guid,
      "gh.webhook.event_type" => hook_event.event_type,
      "gh.repo.id" => hook_event.target_repository.id,
      "gh.repo.global_id" => hook_event.target_repository.global_relay_id
    })
  end

  sig { void }
  def instrument_actions_app_hook_filter
    GitHub.dogstats.increment("actions.hooks.ignored", tags: ["event_type:#{hook_event.event_type}", "reason:actions_triggered_event"])

    GitHub::logger.info("Ignoring Actions hook - event was triggered by Actions", {
      "gh.request_id" => GitHub.context[:request_id],
      "code.namespace" => "Hook::DeliverySystem",
      "code.function" => "filter_actions_hooks",
      "gh.catalog_service" => "github/actions_experience",
      "gh.webhook.delivery_guid" => hook_event.guid,
      "gh.webhook.event_type" => hook_event.event_type,
      "gh.repo.id" => hook_event.target_repository.id,
      "gh.repo.global_id" => hook_event.target_repository.global_relay_id
    })
  end

  # Private Methods

  sig { params(hook_triggered_at: Time).returns(Integer) }
  private_class_method def self.get_actions_hook_age(hook_triggered_at)
    hook_age_seconds = Time.now - hook_triggered_at
    hook_age_seconds = hook_age_seconds.to_i
    # Clock skew could cause hook_age_seconds to be negative by a small amount
    # If this happens, treat the hook as if it were just triggered
    hook_age_seconds = 0 if hook_age_seconds < 0

    hook_age_seconds
  end

  sig { params(hook_age_seconds: Integer).returns(Integer) }
  private_class_method def self.get_actions_hook_ttl(hook_age_seconds)
    return 0 if hook_age_seconds >= ACTIONS_AQUEDUCT_JOB_TTL
    ACTIONS_AQUEDUCT_JOB_TTL - hook_age_seconds
  end

  sig { params(queue: String, payload: T::Hash[T.untyped, T.untyped], hook_triggered_at: Time, hook_age: Integer).void }
  private_class_method def self.log_expired_actions_hook(queue, payload, hook_triggered_at, hook_age)
    delivery_guid = payload[:guid]
    event_type = payload[:event]
    repo_id = payload.dig("payload", "repository", "id")
    GitHub.dogstats.increment("actions.hooks.expired",
      tags: ["queue:#{queue}", "event_type:#{event_type}", "namespace:Hook::DeliverySystem", "function:enqueue_payload_to_hookshot"])
    GitHub::logger.info("Actions hook age exceeds time to live", {
      "gh.request_id" => GitHub.context[:request_id],
      "code.namespace" => "Hook::DeliverySystem",
      "code.function" => "enqueue_payload_to_hookshot",
      "gh.catalog_service" => "github/actions_experience",
      "gh.webhook.queue" => queue,
      "gh.webhook.delivery_guid" => delivery_guid,
      "gh.webhook.event_type" => event_type,
      "gh.webhook.triggered_at" => hook_triggered_at,
      "gh.webhook.age_seconds" => hook_age,
      "gh.webhook.ttl_limit_seconds" => ACTIONS_AQUEDUCT_JOB_TTL,
      "gh.webhook.expired" => true,
      "gh.repo.id" => repo_id,
    })
  end
end
