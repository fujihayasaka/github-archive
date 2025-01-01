# typed: true
# frozen_string_literal: true

class Gists::AssetsController < Gists::ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1

  def show
    asset = UserAsset.where(
      guid: params[:guid],
      upload_container_type: Gist.name,
      state: 1, # uploaded
    ).first

    return render_404 unless asset
    if GitHub.flipper[:restrict_unassociated_user_assets].enabled?
      return render_404 if asset.restricted? && asset.uploader != current_user
    end

    args = GitHub.storage_cluster_enabled? ? { actor: current_user || User.ghost } : {}
    redirect_to asset.redirect_url(**args)
  end

  def legacy_show # rubocop:disable GitHub/UseRestfulActions
    asset = UserAsset.where(
      user_id: params[:user_id],
      guid: params[:guid],
      upload_container_type: Gist.name,
      state: 1, # uploaded
    ).first

    return render_404 unless asset
    return render_404 if asset.using_new_url?

    args = GitHub.storage_cluster_enabled? ? { actor: current_user || User.ghost } : {}
    redirect_to asset.redirect_url(**args)
  end

end
