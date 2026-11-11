# typed: true
# frozen_string_literal: true

class Actions::NavigationPartialController < AbstractRepositoryController
  include ActionsControllerMethods

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::Mysql5,
  ApplicationRecord::Configurations,
  ApplicationRecord::RepositoriesActionsChecks,
  ApplicationRecord::IssuesPullRequests,
  only: [:show]

  around_action :track_and_report_render_view_time, only: [:show, :new]
  around_action :track_and_report_graphql_executions, only: [:show]
  around_action :track_and_report_mysql_executions, only: [:show]
  before_action :login_required, except: [:show]
  before_action :actions_enabled_for_repo?, except: [:show]

  # Used for loading Actions workflow navigation for mobile screen sizes
  def show
    return head :not_found unless request.xhr?
    selected_item_id = selected_workflow&.id || params[:selected_section]&.to_sym
    render partial: "actions/actions_nav_with_pinning", locals: {
      selected_workflow: selected_workflow,
      selected_item_id: selected_item_id,
      workflow_run_filters: workflow_run_filters,
      workflows: workflows,
      workflow_pages_count: workflow_pages_count,
      show_only_required_workflows: show_only_required_workflows?,
      show_runners_view: show_runners_view?,
      show_attestations_view: show_attestations_view?,
      show_actions_usage_metrics: show_actions_usage_metrics?,
      # Pinning is disabled for mobile screen sizes, it shows in the ... menu in the header
      allow_pinning: false,
    }
  end

  def new
    return head :not_found unless request.xhr?
    number_of_templates = params[:number_of_templates]
    show_navigation_category = params[:show_navigation_category]
    render partial: "actions/side_nav", locals: {
      number_of_templates: number_of_templates,
      selected_category: selected_category,
      show_navigation_category: show_navigation_category,
      show_runners_view: show_runners_view?,
    }
  end

  private

  def route_supports_advisory_workspaces?
    parent_repository_can_have_actions_on_private_forks? || super
  end
end
