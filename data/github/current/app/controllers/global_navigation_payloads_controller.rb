# typed: true
# frozen_string_literal: true

class GlobalNavigationPayloadsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  include RepositoryControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:show]

  before_action :render_404, unless: :logged_in?

  allow_verified_fetch only: [:show]

  def show
    if params[:type].nil?
      return render json: GlobalNavigation::DeferredPayload.new(
        current_user: current_user,
        current_copilot_user: current_copilot_user_v2,
        current_repository: current_repository,
        current_organization: helpers.current_organization,
        account_switcher_helper: account_switcher_helper,
        user_can_create_organizations: user_can_create_organizations?,
        memex_enabled: GitHub.projects_new_enabled?,
        show_issue_create_link: FeatureFlag.vexi.enabled_or_raise?(:issues_react_global_add, current_user), # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        display_switch_account_popover: params[:display_switch_account_popover] == "true",
        source: "lazy_loading"
      ).payload(return_to: params[:return_to] || return_to_path)
    end

    respond_to do |format|
      format.json do
        case params[:type]
        when "nav_menu"
          render json: GlobalNavigation::NavMenuPayload.new(
            current_user: current_user,
            current_copilot_user: current_copilot_user_v2,
            source: "lazy_loading"
          ).payload
        when "user_menu"
          render json: GlobalNavigation::UserMenuPayload.new(
            current_user: current_user,
            account_switcher_helper: account_switcher_helper,
            source: "lazy_loading"
          ).payload(return_to: params[:return_to] || return_to_path)
        when "create_menu"
          render json: GlobalNavigation::CreateMenuPayload.new(
            current_user: current_user,
            current_copilot_user: current_copilot_user_v2,
            current_repository: current_repository,
            current_organization: helpers.current_organization,
            user_can_create_organizations: user_can_create_organizations?,
            memex_enabled: GitHub.projects_new_enabled?,
            show_issue_create_link: FeatureFlag.vexi.enabled_or_raise?(:issues_react_global_add, current_user), # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
            source: "lazy_loading"
          ).payload
        when "agents_menu"
          render json: GlobalNavigation::CopilotPayload.new(
            current_user: current_user,
            current_copilot_user: current_copilot_user_v2,
            current_repository: current_repository,
            source: "lazy_loading"
          ).agents_panel_payload
        when "account_switch_dialog"
          render json: GlobalNavigation::AccountSwitchDialogPayload.new(
            current_user: current_user,
            account_switcher_helper: account_switcher_helper,
            display_switch_account_popover: params[:display_switch_account_popover] == "true",
            source: "lazy_loading"
          ).payload
        else
          render_404
        end
      end
    end
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
