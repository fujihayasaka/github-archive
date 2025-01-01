# typed: true
# frozen_string_literal: true

module Codespaces
  class RepositorySettingsController < AbstractRepositoryController
    include ApplicationController::CodespaceTagActionDependency

    before_action :login_required_redirect_for_public_repo
    before_action :require_codespace_access
    before_action :require_codespace_prebuilds_access
    before_action :ensure_admin_access

    javascript_bundle "codespaces-prebuild-configurations"

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Spokes,
      ApplicationRecord::Mysql2,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Iam,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Memex,
      ApplicationRecord::Billing,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    def index
      prebuild_configurations = Codespaces::PrebuildConfiguration.where(
        repository_id: current_repository.id
      ).includes(:locations, latest_workflow_run: [:latest_workflow_run_job, :check_suite] , repository: :owner)
      render "codespaces/repository_settings/index", locals: {
        prebuild_configurations: prebuild_configurations,
        prebuild_usage_message: prebuild_usage_message
      }
    end

    private

    def require_codespace_prebuilds_access
      render_404 unless current_repository&.owner.codespaces_feature_enabled?
    end

    def require_codespace_access
      render_404 unless current_repository.owner&.codespaces_feature_enabled?
    end

    memoize def prebuild_usage_message
      Codespaces::Prebuilds.prebuild_usage_disallowed_message(current_repository&.owner, current_repository)
    end
  end
end
