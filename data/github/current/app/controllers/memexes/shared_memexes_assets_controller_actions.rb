# typed: true
# frozen_string_literal: true

module Memexes
  module SharedMemexesAssetsControllerActions
    extend T::Helpers
    requires_ancestor { ApplicationController }

    def show
      asset = UserAsset.find_by(
        user_id: params[:user],
        guid: params[:guid],
        upload_container_type: "MemexProject",
        state: :uploaded,
      )

      return render_404 unless asset
      return render_404 if asset.using_new_url?

      args = GitHub.storage_cluster_enabled? ? { actor: current_user || User.ghost } : {}
      redirect_to asset.redirect_url(**args)
    end
  end
end
