# typed: false
# frozen_string_literal: true

class Hook::Event::DeploymentProtectionRuleEvent < Hook::Event
  include GitHub::Memoizer

  supports_targets Integration
  description "Deployment protection rule requested for an environment."

  event_attr :specific_app_only, :gate_id, :check_run_id, :action, required: true

  def target_repository
    gate.try(:environment).try(:repository)
  end

  memoize def actor
    User.find_by_id(check_run.check_suite.creator_id)
  end

  def deliverable?
    # is it desired to not deliver the webhook if target_repository/workflow_run are nil?
    target_repository.present? && workflow_run.present? && gate.present?
  end

  memoize def integration
    gate.integration
  end

  # Override subscribed_hooks to only include the specific app's hook.
  # Logic roughly mirrors subscribed_integration_hooks in the base class, verify:
  #   1. integration has access to the repository
  #   2. integration still subscribed to deployment_protection_rule event
  def subscribed_hooks
    if specific_app_only
      return @target_hook if defined?(@target_hook)

      @target_hook = []
      return @target_hook unless integration&.active_and_subscribable?

      # make sure the integration has deployment access to the target repo
      # there should be at most one installation that matches the integration and target repo
      installation_ids = integration.installations.with_resources_on(subject: target_repository, resources: "deployments").pluck(:id)
      return @target_hook unless installation_ids.any?

      # make sure the matched installation is still subscribed to deployment_protection_rule event
      subscribed_installations = HookEventSubscription.with_name_and_subscriber(event_type, "IntegrationInstallation", installation_ids)
      return @target_hook unless subscribed_installations.any?

      @target_hook << integration.hook
      @target_hook
    else
      super
    end
  end

  def subscribed_installations_for(integration_id)
    # specific_app_only lets us send this hook to a specific app instead of any app subscribed to these events
    if specific_app_only && integration.id == integration_id.to_i
      return IntegrationInstallation.none if integration.suspended?

      integration.installations.not_suspended.with_repository(target_repository)
    else
      super
    end
  end

  memoize def gate
    Gate.find(gate_id)
  end

  memoize def check_run
    run = Checks.domain.check_runs.unsafe_for_id(check_run_id)
    raise ActiveRecord::RecordNotFound unless run
    run
  end

  memoize def check_suite
    check_run&.check_suite
  end

  memoize def workflow_run
    check_suite&.workflow_run
  end

  def deployment
    check_run&.deployment
  end

  def pull_requests
    deployment&.pull_requests
  end

  def trigger_event
    check_suite&.event
  end

  def deployment_callback_url
    return unless deliverable?
    "#{GitHub.api_url}/repos/#{target_repository.name_with_display_owner}/actions/runs/#{workflow_run.id}/deployment_protection_rule"
  end
end
