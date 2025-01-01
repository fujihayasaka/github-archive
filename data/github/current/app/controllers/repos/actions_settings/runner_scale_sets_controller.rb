# typed: true
# frozen_string_literal: true

class Repos::ActionsSettings::RunnerScaleSetsController < AbstractRepositoryController
  before_action :login_required
  before_action :ensure_admin_access

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    scale_set_id = params[:id]&.to_i
    scale_set = Actions::RunnerScaleSet.get(current_repository, id: scale_set_id)

    return render_404 unless scale_set

    render "edit_repositories/pages/actions/runner_scale_set",
      locals: {
        scale_set: scale_set,
        owner_settings: Actions::RepoRunnersView.new({
          settings_owner: current_repository,
          current_user: current_user
        }),
      }
  end
end
