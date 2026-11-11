# typed: strict
# frozen_string_literal: true

class Repos::SecretScanning::PushProtectionController < AbstractRepositoryController
  include ApplicationController::VerifiedFetchDependency

  depends_on_clusters(
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
  )

  before_action :login_required

  allow_verified_fetch only: [
    :custom_message,
  ]

  sig { void }
  def custom_message # rubocop:todo GitHub/UseRestfulActions
    repo = T.let(current_repository, Repository)
    return render_404 if repo.nil?
    return render_404 unless current_user_can_push?

    msg = SecretScanning::Services::PushProtectionService.get_custom_message(repo)
    return render json: nil if msg.nil?

    render json: {
      owner_name: msg.owner_name,
      message: msg.message,
    }
  end

  protected

  sig { override.returns(T.nilable(User)) }
  def authentication_methods
    login_from_authorization_header_auth
  end

end
