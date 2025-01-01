# typed: true
# frozen_string_literal: true

class Network::Dependabot::JobsController < GitContentController
  skip_before_action :try_to_expand_path
  before_action :ensure_dependabot_available

  layout "repository"
  stylesheet_bundle :insights

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Permissions,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  sig { void }
  def index
    update_config = nil

    begin
      response = Dependabot::Twirp.update_jobs_client.list_update_jobs(
        repository_id: current_repository.id,
        update_config_id: params[:update_config_id].to_i,
      )
      update_config = response.update_config
      update_jobs = response.update_jobs
    rescue Dependabot::Twirp::ServiceUnavailableError
      return render_404
    rescue Dependabot::Twirp::Error => error
      return render_404
    end

    return render_404 if update_config.nil? || update_jobs.nil?

    respond_to do |format|
      format.html do
        render "network/dependabot/jobs/show", locals: {
          update_config: update_config,
          update_jobs: update_jobs,
        }
      end
    end
  end

  private

  sig { void }
  def ensure_dependabot_available
    render_404 unless current_repository.automated_dependency_updates_visible_to?(current_user)
  end
end
