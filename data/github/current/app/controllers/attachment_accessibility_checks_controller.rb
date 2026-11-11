# typed: strict
# frozen_string_literal: true

# Checks whether user-attachment GUIDs would be inaccessible to other
# viewers of the destination repository.
#
# This is used by the markdown editor to warn authors before they save
# an issue or comment that contains attachments from a private/internal
# repo that other viewers cannot access.
class AttachmentAccessibilityChecksController < ApplicationController
  include RepositoryControllerMethods
  include ApplicationController::VerifiedFetchDependency
  include GitHub::ResilienceMixin

  allow_verified_fetch only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:show]

  before_action :login_required

  MAX_ATTACHMENT_GUIDS = 100
  GUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  sig { void }
  def show
    return render_404 unless current_repository
    return render_404 unless current_repository.can_be_interacted_with_by?(current_user)

    unless FeatureFlag.vexi.enabled?(:warn_inaccessible_attachments, current_repository.owner, default: false)
      return render json: { inaccessible: [] }
    end

    guids = Array(params[:guids]).map(&:to_s).select { |g| g.match?(GUID_PATTERN) }.uniq.first(MAX_ATTACHMENT_GUIDS)

    if guids.empty?
      return render json: { inaccessible: [] }
    end

    inaccessible_guids = with_database_error_fallback(fallback: nil) do
      assets = UserAsset.includes(:repository).where(guid: guids, state: :uploaded).limit(MAX_ATTACHMENT_GUIDS)
      assets_by_guid = assets.index_by(&:guid)

      guids.select do |guid|
        asset = assets_by_guid[guid]
        asset.nil? || cross_repo_inaccessible?(asset)
      end
    end

    render json: { inaccessible: inaccessible_guids || [] }
  end

  private

  # An asset is cross-repo inaccessible when it belongs to a different
  # repository that is not publicly visible.  Viewers of the destination
  # repo who lack access to the source repo will get a 404.
  sig { params(asset: UserAsset).returns(T::Boolean) }
  def cross_repo_inaccessible?(asset)
    source_repo = asset.repository
    return false unless source_repo
    return false if source_repo.id == current_repository.id

    !source_repo.public?
  end
end
