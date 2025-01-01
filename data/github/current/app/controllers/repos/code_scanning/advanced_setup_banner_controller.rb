# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::AdvancedSetupBannerController < AbstractRepositoryController
  include CodeScanning::ControllerAccessChecks

  before_action :login_required,
    :check_code_scanning_read

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
    ApplicationRecord::Notify,
    only: [:show]

  def show
    return render_404 unless request.xhr?

    default_ref = current_repository.default_branch_ref
    return render_404 unless default_ref.present?

    tool_status_response = GitHub::Turboscan.get_tool_status(
      repository_id: current_repository.id,
      ref: default_ref.qualified_name.b,
    )

    raise StandardError.new("Tool status response was nil.") if tool_status_response.nil?
    raise StandardError.new(tool_status_response.error&.msg) if tool_status_response.error.present?
    raise StandardError.new("Tool status response was missing data.") if tool_status_response.data.nil?

    advanced_setup_requested_response = GitHub::Turboscan.get_advanced_setup_requested(repository_id: current_repository.id)
    raise StandardError.new("Advanced setup requested response was nil.") if advanced_setup_requested_response.nil?
    raise StandardError.new(advanced_setup_requested_response.error&.msg) if advanced_setup_requested_response.error.present?

    respond_to do |format|
      format.html do
        render CodeScanning::AdvancedSetupStatusComponent.new(repository: current_repository, tools: T.must(tool_status_response.data).tools, advanced_setup_requested: advanced_setup_requested_response.data.advanced_setup_requested_at.present?), layout: false
      end
    end
  end
end
