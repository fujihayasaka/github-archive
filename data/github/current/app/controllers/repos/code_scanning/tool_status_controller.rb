# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::ToolStatusController < Repos::CodeScanning::ToolStatus::AbstractController
  extend T::Sig

  include DocsUrlHelper

  before_action :login_required,
    :check_code_scanning_read,
    :default_branch_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::RepositoriesActionsChecks,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show], optional: true

  track_latency_slo "p99-ui-request", 3000, only: [:index, :show]
  track_latency_slo "p50-ui-request", 750, only: [:index, :show]

  def index
    unless request.xhr?
      return redirect_to repository_code_scanning_results_tool_status_show_path(tool_name: tools.first.name) unless tools.empty?
      return redirect_to repository_code_scanning_results_path
    end

    after_response do
      tools.each do |tool|
        CodeScanning::Status.emit_tool_status_hydro_event("index_page", current_repository.id, ref, tool, messages)
      end
    end

    render CodeScanning::ToolStatus::OverviewComponent.new(
      current_repository: current_repository,
      tools: tools,
      messages: messages,
    ), layout: false
  end

  def show
    # We would prefer to show any tool rather than none, so we redirect to the first tool if possible
    tool = tools.find { |t| t.name == params[:tool_name] }
    if tool.nil?
      return redirect_to repository_code_scanning_results_tool_status_show_path(tool_name: tools.first.name) unless tools.empty?
      return redirect_to repository_code_scanning_results_path
    end

    after_response do
      CodeScanning::Status.emit_tool_status_hydro_event("show_page", current_repository.id, ref, tool, messages)
    end

    configuration_groups = ::CodeScanning::ToolConfigurationGroup.build_groups(
      repository: current_repository,
      tool: tool,
      messages: messages,
      workflows: workflows,
    )

    render "repos/code_scanning/tool_status/show", locals: {
      current_repository: current_repository,
      tool: tool,
      tools: tools,
      messages: messages,
      workflows: workflows,
      configuration_groups: configuration_groups,
    }
  end
end
