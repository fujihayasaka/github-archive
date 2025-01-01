# typed: true
# frozen_string_literal: true

class CodeScanning::ToolStatus::DeleteConfigurationDialogComponent < ApplicationComponent
  attr_reader :dialog_id
  attr_reader :data
  attr_reader :repository

  def initialize(dialog_id:, repository:, tool_name:, category:, configuration_group_slug:)
    @dialog_id = dialog_id
    @repository = repository
    @tool_name = tool_name
    @configuration_group_slug = configuration_group_slug
    @data = {
      tool_name: tool_name,
      category: category,
      branch_name: repository.default_branch
    }
  end

  def success_path
    repository_code_scanning_results_tool_status_configurations_path(
      user_id: repository.owner_display_login,
      repository: repository,
      tool_name: @tool_name,
      configuration_group: @configuration_group_slug
    )
  end
end
