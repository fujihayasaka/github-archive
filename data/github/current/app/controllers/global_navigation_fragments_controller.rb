# typed: true
# frozen_string_literal: true

class GlobalNavigationFragmentsController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  include RepositoryControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:show]

  allow_verified_fetch only: [:show]

  class DetermineScopeError < StandardError
    def initialize(error)
      super
      set_backtrace(error.backtrace)
    end
  end

  SUPPORTED_SCOPE_CLASS_NAMES = %w[
    User
    Organization
    Repository
    Issue
    Discussion
    PullRequest
    MemexProject
  ].freeze

  def show
    respond_to do |format|

      view = Site::HeaderView.new(
        current_user: current_user,
        current_repository: current_repository,
        current_organization: helpers.current_organization,
        is_mobile_request: mobile?,
        current_copilot_user: current_copilot_user_v2,
        params: params,
        response: response,
      )

      format.html_fragment do
        case params[:type]
        when "mobile_search"
          render partial: "site/header/search", formats: :html, locals: {
            view: view,
            is_search_page: params[:is_search_page] == "true",
          }
        when "search"
          render partial: "site/header/search_redesigned", formats: :html, locals: {
            view: view,
            is_search_page: params[:is_search_page] == "true",
          }
        when "blackbird_search"
          render partial: "site/header/blackbird_search", formats: :html, locals: {
            view: view,
            is_search_page: params[:is_search_page] == "true",
            scope: params[:scope],
            current_repo_nwo: params[:current_repo_nwo],
            current_repo_org: params[:org],
            current_repo_owner: params[:user_id],
            current_business: params[:business_context],
          }
        when "command_palette"
          render partial: "site/header/command_palette", formats: :html, locals: {
            staff_bar_enabled: staff_bar_enabled?,
            scope: determine_scope,
            page_breadcrumb: page_breadcrumb_object,
          }
        else
          render_404
        end
      end
    end
  end

  private

  memoize def this_user
    User.find_by(type: "User", login: params[:user_id])
  end

  def determine_scope
    return if params[:clear_command_scope].present?

    scope = page_breadcrumb_object if SUPPORTED_SCOPE_CLASS_NAMES.include?(page_breadcrumb_object.class.name)
    scope ||= current_repository || helpers.current_organization || this_user

    if scope&.persisted?
      scope
    else
      nil
    end
  rescue StandardError => e
    Failbot.report(DetermineScopeError.new(e))
    GitHub.dogstats.increment("command_palette.determine_scope.error")
    nil
  end

  memoize def page_breadcrumb_object
    case params[:command_scope_type]
    when "Issue"
      Issue.find_by(id: params[:command_scope_id])
    when "Discussion"
      Discussion.find_by(id: params[:command_scope_id])
    when "PullRequest"
      PullRequest.find_by(id: params[:command_scope_id])
    when "MemexProject"
      MemexProject.find_by(id: params[:command_scope_id])
    when "Repository"
      Repository.find_by(id: params[:command_scope_id])
    when "Organization"
      Organization.find_by(id: params[:command_scope_id])
    when "User"
      User.find_by(id: params[:command_scope_id])
    end
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
