# typed: true
# frozen_string_literal: true

class Repos::CodeScanning::ToolStatus::BannerController < Repos::CodeScanning::ToolStatus::AbstractController
  include FeatureFlagHelper

  before_action :login_required,
    :check_code_scanning_read,
    :default_branch_required

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
    only: [:show], optional: true

  track_latency_slo "p99-ui-request", 3000, only: [:show]
  track_latency_slo "p50-ui-request", 750, only: [:show]

  def show
    return render_404 unless request.xhr?

    respond_to do |format|
      format.html do
        component = CodeScanning::ToolStatus::NoticeComponent.new(messages: messages, repository: current_repository)
        if component.render?
          render html: view_context.render(component), layout: false
        else
          # Return empty response when no banner should be shown
          head :ok
        end
      end
    end
  end
end
