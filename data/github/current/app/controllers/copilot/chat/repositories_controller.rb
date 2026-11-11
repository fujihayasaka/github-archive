# typed: true
# frozen_string_literal: true

class Copilot::Chat::RepositoriesController < Copilot::Chat::AbstractChatController
  before_action :require_repository
  before_action :require_readable_repository_for_direct_access

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
    repo = Repositories.domain.by_id(params[:id].to_i)
  end

  memoize def current_repository_with_nwo
    repo = Repository.nwo("#{params[:user_id]}/#{params[:repository]}")
  end

  def require_repository
    render_404 unless current_repository
  end

  # NOTE: Unlike AbstractChatController's handling of unreadable repositories
  # (which may treat them as nil to avoid enumeration), this guard always
  # renders 404 when the current user cannot read the repository. This
  # stricter behavior is intended for this controller's direct-access
  # endpoint(s) and should not be reused where the "nilify" semantics are
  # required for enumeration safety.
  def require_readable_repository_for_direct_access
    render_404 unless current_user_can_read_repo?
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
