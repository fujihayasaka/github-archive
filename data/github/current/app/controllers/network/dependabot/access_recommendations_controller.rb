# typed: true
# frozen_string_literal: true

class Network::Dependabot::AccessRecommendationsController < GitContentController
  skip_before_action :try_to_expand_path
  before_action :ensure_dependabot_available
  before_action :ensure_account_adminable
  before_action :ensure_org_repository
  before_action :ensure_repository_access_feature_enabled

  layout "repository"

  def apply # rubocop:todo GitHub/UseRestfulActions
    update_config_id = params.require(:update_config_id).to_i
    repository_ids = params.require(:repository_ids).map(&:to_i)
    repositories = owner.repositories.where(id: repository_ids)

    Dependabot::RepositoryAccess.for(org: owner, actor: current_user).append(repository_ids: repositories.pluck(:id))

    begin
      Dependabot::Twirp.update_configs_client.trigger_update_job(
        repository_id: current_repository.id,
        update_config_id: update_config_id
      )
    rescue Dependabot::Twirp::Error, Dependabot::Twirp::ServiceUnavailableError
      # No sweat. At this point, the error has been reported to Failbot, and the
      # user can manually re-trigger the job.
    end

    redirect_to network_dependabot_path,
      flash: { notice: "Granted Dependabot access to #{repositories.map(&:name_with_display_owner).to_sentence}." }
  end

  private

  def ensure_dependabot_available
    render_404 unless current_repository.automated_dependency_updates_visible_to?(current_user)
  end

  def ensure_account_adminable
    render_404 unless owner.adminable_by?(current_user)
  end

  def ensure_org_repository
    render_404 unless owner.organization?
  end

  def ensure_repository_access_feature_enabled
    render_404 unless owner.dependabot_repository_access_enabled_for?(current_user)
  end
end
