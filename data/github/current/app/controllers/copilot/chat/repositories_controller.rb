# typed: true
# frozen_string_literal: true

class Copilot::Chat::RepositoriesController < Copilot::Chat::AbstractChatController
  before_action :require_repository

  depends_on_clusters(
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    only: [:show],
  )

  def show
    render json: helpers.repo_props(repo: current_repository)
  end

  private

  def current_repository
    current_repository_with_id || current_repository_with_nwo
  end

  memoize def current_repository_with_id
    repo = if FeatureFlag.vexi.enabled?(:repos_domain_controllers, default: false)
      Repositories.domain.by_id(params[:id].to_i)
    else
      Repository.find_by(id: params[:id])
    end
  end

  memoize def current_repository_with_nwo
    repo = Repository.nwo("#{params[:user_id]}/#{params[:repository]}")
  end

  def require_repository
    render_404 unless current_repository
  end

  # CAP is not bypassed here as repo is required by :require_repository
  def resource_for_conditional_access
    return current_repository if current_repository
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  # CAP is not bypassed here as AbstractChatController requires a logged in user
  def target_for_conditional_access
    return current_repository.owner if current_repository
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end
