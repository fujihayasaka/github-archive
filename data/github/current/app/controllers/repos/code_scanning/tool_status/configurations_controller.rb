# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::ToolStatus::ConfigurationsController < Repos::CodeScanning::ToolStatus::AbstractController
  before_action :login_required,
    :check_code_scanning_read,
    :default_branch_required,
    :redirect_if_no_tool,
    :redirect_if_no_configuration_group

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::RepositoriesActionsChecks,
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
    only: [:index, :show],
    optional: true

  track_latency_slo "p99-ui-request", 3000, only: [:index, :show]
  track_latency_slo "p50-ui-request", 750, only: [:index, :show]

  def index
    render "repos/code_scanning/tool_status/configurations/index", locals: {
      tool: tool,
      configuration_group: configuration_group,
      configurations: configurations,
      messages: messages,
    }
  end

  def show
    selected_configuration = configurations.find { |c| c.slug == params[:configuration] }

    return redirect_to repository_code_scanning_results_tool_status_configurations_path if selected_configuration.nil?

    locals = {
      tool: tool,
      configuration_group: configuration_group,
      configurations: configurations,
      selected_configuration: selected_configuration,
      messages: messages,
      delete_configuration_dialog_id: "delete-configuration-dialog-id",
    }

    render "repos/code_scanning/tool_status/configurations/show", locals: { **locals }
  end

  private

  sig { returns T.nilable(CodeScanning::ToolConfigurationGroup) }
  memoize def configuration_group
    configuration_groups = ::CodeScanning::ToolConfigurationGroup.build_groups(repository: current_repository, tool: tool, messages: messages, workflows: workflows)
    configuration_groups.find { |group| group.slug == params[:configuration_group] }
  end

  sig { returns(T::Array[CodeScanning::ToolConfiguration]) }
  memoize def configurations
    T::must(configuration_group).categories.map do |category|
      CodeScanning::ToolConfiguration.new(
        category: category,
        overall_status: ::CodeScanning::Status.max_level(messages.fetch(tool.name, category))
      )
    end
  end

  memoize def tool
    tools.find { |t| t.name == params[:tool_name] }
  end

  def redirect_if_no_tool
    redirect_to repository_code_scanning_results_tool_status_show_path if tool.nil?
  end

  def redirect_if_no_configuration_group
    redirect_to repository_code_scanning_results_tool_status_show_path if configuration_group.nil?
  end
end
