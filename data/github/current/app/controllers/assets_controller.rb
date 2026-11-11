# typed: true
# frozen_string_literal: true

class AssetsController < AbstractRepositoryController
  skip_before_action :authorization_required, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  def show
    asset = UserAsset.where(
      guid: params[:guid],
      user_id: params[:user],
      state: :uploaded,
    ).first

    return render_404 unless asset
    return render_404 if asset.using_new_url?
    return render_404 unless asset.has_access?(current_user)

    redirect_to asset.redirect_url(actor: current_user, secure_user_assets: true)
    expires_in 5.minutes
  end
end
