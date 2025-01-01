# typed: strict
# frozen_string_literal: true

class RepositoryInstallations::ActionsController < AbstractRepositoryController
  extend T::Sig

  before_action :ensure_current_user_has_feature_enabled
  before_action :ensure_current_installation_exists

  layout false

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Permissions

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show], optional: true

  sig { void }
  def show
    result = IntegrationInstallation::Permissions.check(
      installation: T.must(current_installation),
      actor: current_user,
      action: :configure_access_to_repository,
      repository: current_repository
    )

    render "repository_installations/actions/show", locals: {
      installation: T.must(current_installation), result: result
    }
  end

  private

  sig { returns(T.nilable(IntegrationInstallation)) }
  memoize def current_installation
    IntegrationInstallation.includes(:integration).find_by(
      target: current_repository.owner,
      id: params[:installation_id]
    )
  end

  sig { void }
  def ensure_current_installation_exists
    render_404 unless current_installation
  end

  sig { void }
  def ensure_current_user_has_feature_enabled
    render_404 unless current_user.feature_enabled?(:fast_repository_installations)
  end

  sig { void }
  def privacy_check
    return true if current_repository.adminable_by?(current_user)

    render_404
  end
end
