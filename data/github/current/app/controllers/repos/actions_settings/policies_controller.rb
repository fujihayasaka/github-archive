# typed: true
# frozen_string_literal: true

class Repos::ActionsSettings::PoliciesController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_admin_access

  def update_allowed_actions # rubocop:todo GitHub/UseRestfulActions
    policy = params[:allowedactions].to_s

    unless Actions::Policy::AllowedActionsForm::VALID_OPTIONS.include?(policy) || policy == Actions::PolicyUpdater::DISABLED
      flash[:error] = "Sorry, there was an issue updating your settings."

      return redirect_to repository_actions_settings_path
    end

    disable_actions = policy == Actions::PolicyUpdater::DISABLED
    access_policy = disable_actions ? Actions::PolicyUpdater::DISABLED : Configurable::ActionsAccess::ALL_ENTITIES

    Actions::PolicyUpdater.perform(
      entity: current_repository,
      policy: access_policy,
      actor: current_user,
    )

    if Actions::Policy::AllowedActionsForm::VALID_OPTIONS.include? policy
      if policy == Actions::Policy::AllowedActionsForm::SPECIFIED_ACTIONS
        # If both were not passed, just set one of them for now.
        params["firstparty"] = true unless %w(firstparty marketplace patterns).any? { |k| params.key? k }
        current_repository.enable_specified_actions_only(github_owned: params["firstparty"] || false, verified: params["marketplace"] || false, actor: current_user)

        if params[:patterns]
          patterns = params[:patterns].split(/,\s*/).map(&:strip)
          allowlist = ActionsPolicy::Allowlist.update_or_create_with_patterns(current_repository, patterns: patterns, actor: current_user)
        end
      else
        Actions::AllowedTypesUpdater.perform(entity: current_repository, policy: policy, actor: current_user)
      end
    end

    if allowlist && allowlist.errors.any?
      flash[:error] = allowlist.errors.full_messages.to_sentence
    else
      flash[:notice] = "Actions policy updated."
    end

    redirect_to repository_actions_settings_path
  end
end
