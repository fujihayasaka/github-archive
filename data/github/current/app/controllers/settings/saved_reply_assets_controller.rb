# typed: true
# frozen_string_literal: true

module Settings
  class SavedReplyAssetsController < ApplicationController

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab

    before_action :login_required

    def show
      asset = UserAsset.where(
        guid: params[:guid],
        user_id: params[:user],
        upload_container_type: User.name,
        upload_container_id: params[:user],
        state: 1, # uploaded
      ).first

      return render_404 unless asset
      return render_404 if asset.using_new_url?
      return render_404 unless asset.has_access?(current_user)

      redirect_to asset.redirect_url(actor: current_user)
    end

    private

    def target_for_conditional_access
      current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end

  end
end
