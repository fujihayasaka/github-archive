# typed: false
# frozen_string_literal: true

require "openssl"

# Accepts image and video file uploads from the issue/pull request/discussion
# comment forms. This is typically triggered by dragging and dropping images
# onto the browser window.
class UploadsController < ApplicationController
  before_action :login_required
  before_action :ensure_asset

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:update]

  # double the default rate limit that ApplicationController sets
  rate_limit_requests only: [:update], max: 2000, ttl: 1.hour

  # Signal that the upload completed successfully. The browser performs an
  # ajax PUT request to /upload/:id after the file is successfully uploaded
  # to S3.
  #
  # Returns nothing.
  def update
    # save the digest for Release Attestations
    if current_asset.is_a?(ReleaseAsset)
      # capture the asset digest and hmac from memory-alpha
      digest      = request.headers["X-Digest-Sha256"]
      digest_hmac = request.headers["X-Digest-Sha256-Hmac"]

      # if the digest is present, validate it and persist as part of release asset
      if digest.present?
        # HMAC validation to ensure the digest is from memory-alpha
        unless GitHub::AssetDigestHmacValidator.verify_digest_hmac(asset_policy_key, digest, digest_hmac)
          return render(status: 400, json: { errors: ["invalid asset checksum"] })
        end

        current_asset.digest = "sha256:#{digest}"
      end
    end

    track_uploaded = current_asset.track_uploaded

    track_execution_time(
      model: params[:model],
      image_content: image?,
      video_content: video?,
      success: track_uploaded
    ) do
      if track_uploaded
        GitHub.dogstats.increment("svg.upload.success") if svg?
        render status: 200, json: current_asset.storage_policy.asset_hash
      else
        GitHub.dogstats.increment("svg.upload.failure") if svg?
        render status: 400, json: { errors: current_asset.errors.full_messages }
      end
    end
  end

  private

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def current_asset # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @current_asset ||=
      case params[:model]
      when "assets"
        find_assets
      when "repository-files"
        find_repository_files
      when "repository-images"
        find_repository_images
      when "upload-manifest-files"
        find_upload_manifest_files
      when "releases"
        find_releases
      when "marketplace_listing_screenshots"
        find_marketplace_screenshots
      when "marketplace_listing_images"
        find_marketplace_listing_images
      when "oauth_applications"
        find_oauth_applications
      when "copilot-chat-attachments"
        find_copilot_chat_attachments
      end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def ensure_asset
    valid_asset = current_asset.present?
    case current_asset
    when ReleaseAsset, RepositoryFile, UploadManifestFile, RepositoryImage
      valid_asset = valid_asset && current_asset.repository
    end
    render(status: 404, json: { errors: ["Invalid Asset"] }) unless valid_asset
  end

  def find_assets
    UserAsset.find_by(id: params[:id], user_id: current_user.id)
  end

  def find_releases
    asset = Releases::Public.load_asset(params[:id].to_i)
    asset&.uploader_id == current_user.id ? asset : nil
  end

  def find_oauth_applications
    OauthApplicationLogo.find_by(id: params[:id], uploader_id: current_user.id)
  end

  def find_repository_files
    RepositoryFile.where(id: params[:id], uploader_id: current_user.id).first
  end

  def find_repository_images
    RepositoryImage.where(id: params[:id], uploader_id: current_user.id).first
  end

  def find_upload_manifest_files
    UploadManifestFile.where(id: params[:id], uploader_id: current_user.id).first
  end

  def find_marketplace_screenshots
    Marketplace::ListingScreenshot.where(id: params[:id], uploader_id: current_user.id).first
  end

  def find_marketplace_listing_images
    Marketplace::ListingImage.where(id: params[:id], uploader_id: current_user.id).first
  end

  def find_copilot_chat_attachments
    if user_feature_enabled?(:copilot_chat_attachments)
      Copilot::ChatAttachment.where(id: params[:id], uploader_id: current_user.id).first
    end
  end

  def target_for_conditional_access
    case current_asset
    when ReleaseAsset, RepositoryFile, UploadManifestFile, RepositoryImage
      # Possible if, for example, the repo gets deleted in the middle of the upload process
      return :no_target_for_conditional_access unless current_asset.repository # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_asset.repository.owner
    when UserAsset
      current_asset.uploader
    when Marketplace::ListingScreenshot, Marketplace::ListingImage
      current_asset.listing.owner
    when OauthApplicationLogo
      # Test performs an upload with no OAuth Application ID
      return :no_target_for_conditional_access unless current_asset.oauth_application # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_asset.oauth_application.owner
    when Copilot::ChatAttachment
      current_asset.target_for_conditional_access
    when nil
      # Will 404 in `ensure_asset`
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end

  def svg?
    ::Storage::Uploadable::SVG_CONTENT_TYPE.include?(current_asset.content_type)
  end

  def image?
    ::Storage::Uploadable::IMAGE_CONTENT_TYPES.include?(current_asset.content_type)
  end

  def video?
    ::Storage::Uploadable::VIDEO_CONTENT_TYPES.include?(current_asset.content_type)
  end

  def track_execution_time(**kwargs)
    start_time = GitHub::Dogstats.monotonic_time
    result = yield
    elapsed = GitHub::Dogstats.duration(start_time)

    GitHub.dogstats.distribution(
      "uploads.update.dist.time",
      elapsed,
      tags: kwargs.map { |k, v| "#{k}:#{v}" }
    )

    result
  end

  # Private: The value from the form hash in the upload policy
  # Memory-Alpha uses this as part of the HMAC signature
  #
  # Returns the key value used in the upload policy provided to Memory-Alpha
  def asset_policy_key
    current_asset.storage_policy.policy_hash.dig(:form, :key)
  end
end
