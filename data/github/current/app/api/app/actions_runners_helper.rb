# typed: true
# frozen_string_literal: true

require "github-launch"
require "github/launch_client"

module Api::App::ActionsRunnersHelper
  include Platform::Authorization
  include Api::App::ErrorDependency
  include Api::App::TwirpHelpers

  private

  # Calling this method in a route allows the runner to access this endpoint during registration
  # This is needed so the runner can fetch groups and de-dupe runner names during interactive configuration
  def attempt_runner_registration_login(entity)
    return unless entity.feature_enabled?(:actions_runners_use_runner_admin_service)
    # If the runner is registering via runner-admin, we allow read-only access to certain endpoints
    scope = entity.runner_creation_token_scope
    attempt_remote_token_login scope
  end

  def repo_runners_enabled?
    GitHub.actions_enabled?
  end

  def org_runners_enabled?
    GitHub.actions_enabled?
  end

  def can_use_org_runners?(organization)
    Billing::ActionsPermission.new(organization).status[:error][:reason] != "PLAN_INELIGIBLE"
  end

  def enterprise_runners_enabled?(enterprise)
    return false if enterprise.downgraded_to_free_plan?
    GitHub.actions_enabled?
  end

  def validate_runner_groups_response!(response)
    unless response
      Failbot.report(StandardError.new("no response from list"), launch_runnergroups: Launch::Twirp.runner_groups_client)
      deliver_error!(503, message: "Runner Groups unavailable. Please try again later.")
    end
  end

  def validate_self_hosted_runners_response!(response)
    unless response
      Failbot.report(StandardError.new("no response from list"), launch_selfhostedrunners: Launch::Twirp.self_hosted_runners_client)
      deliver_error!(503, message: "Runners unavailable. Please try again later.")
    end
  end

  def ensure_tenant!(entity)
    handle_twirp_errors do
      Launch::Twirp.deployer_client.setup_tenant(entity)
    end
  end

  def get_global_id(entity)
    !GitHub.enterprise? ? entity.next_global_id : entity.global_relay_id
  end

  def ensure_no_runners_in_group(entity, runner_group_id)
    runner_group = Actions::RunnerGroup.get(entity, id: runner_group_id, include_runners: true)

    if runner_group.nil?
      deliver_error! 404, message: "Runner group does not exist."
    end

    if runner_group.runners&.length > 0
      deliver_error! 422, message: "This group cannot be deleted because it contains runners. Please remove or move them to another group before proceeding."
    end

    if entity.can_use_larger_runners?
      larger_runners = Actions::LargerRunner.larger_runners_for(entity: entity)

      if larger_runners.any? { |r| r.runner_group_id == runner_group.id }
        deliver_error! 422, message: "This group cannot be deleted because it contains runners. Please remove or move them to another group before proceeding."
      end
    end
  end

  def get_name_parameter
    return params[:name] if params[:name].present?
    return params[:agentName] if params[:agentName].present?
    ""
  end
end
