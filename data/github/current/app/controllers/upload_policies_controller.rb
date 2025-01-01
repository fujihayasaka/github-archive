# typed: false
# frozen_string_literal: true

# The file upload flow is three steps:
#
#   1. POST to /upload/policies to create the policy document validating the file
#      upload.
#   2. POST the file upload form to the endpoint specified by the policy.
#   3. PUT to /upload/:asset_id to signal that the file upload completed
#      successfully.
#
# All three steps are carried out by the JavaScript uploader code in
# uploads.coffee when triggered by a drag-and-drop of files onto a comment
# form field.
#
# This controller implements step one. See UploadController for steps two and
# three.
class UploadPoliciesController < ApplicationController
  include UploadHelper
  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:create]

  before_action :login_required

  include GitHub::RateLimitedRequest
  # This rate limits assets upload policy creation to 100 per user per hour.
  rate_limit_requests \
    only: [:create],
    if: :upload_policy_assets_rate_limit_filter,
    key: :upload_policy_assets_rate_limit_key,
    log_key: :upload_policy_assets_rate_limit_log_key,
    max: 100,
    ttl: 1.hour,
    at_limit: :upload_policy_rate_limit_record

  # We POST to this action over ajax to generate a policy document before POSTing
  # the file upload to S3.
  #
  # Amazon requires a policy document signed with our secret key to be submitted
  # along with the file upload to ensure only users of our app are allowed to
  # store files in our buckets.
  #
  # More info on the form fields required by S3 here:
  #
  #   http://aws.amazon.com/articles/1434
  #
  # Returns nothing.
  def create
    return render_404 unless uploader = ::Storage.policy_creator.for(model_name)

    # The CodeqlDatabase model does not support uploading through the UI
    # and must use the alambic uploader. This is necessary because
    # CodeqlDatabase does not implement an authorization check on save.
    # See https://github.com/github/github/pull/201978 and https://github.com/github/github/pull/202124 for more info.
    return render_404 if model_name == "codeql_databases"

    if msg = ensure_paid_account_for_oversized_videos(uploader.model)
      return render status: 422, json: { errors: [{ field: "size", message: msg }] }
    end

    if GitHub.storage_cluster_enabled?
      create_with_storage_policy(uploader.model)
    else
      track_execution_time(
        model: model_name,
        image_content: image?,
        video_content: video?
      ) do
        deliver_policy uploader.create(current_user, policy_params(params))
      end
    end
  end

  private

  def create_with_storage_policy(uploadable_class)
    meta = {}
    uploadable_class.uploadable_policy_attributes.each do |key|
      meta[key] = params[key]
    end

    if params[:business_id]
      business = Business.where(slug: params[:business_id]).first!
      meta[:business_id] = business.id
    end

    meta = meta.merge(map_upload_container_type(params[:upload_container_type])) if params[:upload_container_type]

    blob = ::Storage::Blob.new(size: meta[:size])
    deliver_policy uploadable_class.storage_new(current_user, blob, meta)
  end

  def policy_params(params)
    if params[:business_id]
      business = Business.where(slug: params[:business_id]).first!
      return params.merge(business_id: business.id)
    end

    return params.merge(map_upload_container_type(params[:upload_container_type])) if params[:upload_container_type]

    params
  end

  def map_upload_container_type(upload_container_type)
    type_map = {
      "project" => MemexProject.name,
      "blob" => UserAsset::REPOSITORY_BLOB,
      "user" => User.name,
      "gist" => Gist.name,
    }

    { upload_container_type: type_map[upload_container_type] }
  end

  def deliver_policy(uploadable)
    if uploadable.valid?
      policy = uploadable.storage_policy(actor: current_user)
      increment_logo_stat(uploadable)
      render status: 201, json: add_authenticity_tokens(policy.policy_hash)
      return true
    end

    if !uploadable.upload_access_allowed?(current_user)
      render_404
      return false
    end

    extra = {
      model_name: uploadable.class.name,
    }

    uploadable.errors.each do |error|
      extra["#{error.attribute}_error"] = error.message
    end

    err = StandardError.new("Failed to create #{uploadable.class.name}")
    GitHub.logger.error(
      "Failed to deliver policy",
      {
        :exception =>  err,
        "code.namespace" => uploadable.class.name,
        "code.function" => __method__,
        "error.extra" => extra
      }
    )
    Failbot.report_user_error(err)

    render status: 422,
      json: { errors: Api::Serializer.validation_errors(uploadable.errors) }
    false
  end

  def add_authenticity_tokens(policy_hash)
    if upload_url = policy_hash[:upload_url]
      token = authenticity_token_for(upload_url)
      policy_hash[:upload_authenticity_token] = token
    end

    if asset_upload_url = policy_hash[:asset_upload_url]
      token = authenticity_token_for(asset_upload_url, method: :put)
      policy_hash[:asset_upload_authenticity_token] = token
    end

    policy_hash
  end

  def media?
    ::Storage::Uploadable::CONTENT_TYPES[:media].include?(params[:content_type])
  end

  def video?
    ::Storage::Uploadable::VIDEO_CONTENT_TYPES.include?(params[:content_type])
  end

  def image?
    ::Storage::Uploadable::IMAGE_CONTENT_TYPES.include?(params[:content_type])
  end

  def svg?
    ::Storage::Uploadable::SVG_CONTENT_TYPE.include?(params[:content_type])
  end

  def increment_logo_stat(uploadable)
    return unless uploadable.is_a?(OauthApplicationLogo)
    GitHub.dogstats.increment("oauth_application", tags: ["action:logo_created"])
  end

  def model_name # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @model_name ||= begin
      model_name = params[:model]

      if model_name == "assets" && params[:repository_id].present? && !media?
        model_name = "repository-files"
      end

      model_name
    end
  end

  def target_for_conditional_access
    case model_name
    when "assets", "repository-files", "upload-manifest-files", "repository-images", "codeql_databases"
      repo = if GitHub.flipper[:upload_policies_tfca_read_only].enabled?(current_user)
        ActiveRecord::Base.connected_to(role: :reading) { Repository.find_by_id(params[:repository_id]) }
      else
        Repository.find_by_id(params[:repository_id])
      end
      # Can upload without a repository ID
      return :no_target_for_conditional_access unless repo # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      repo.owner
    when "releases"
      release = Releases::Public.load_release(params[:release_id].to_i)
      # Redirects to login page
      return :no_target_for_conditional_access unless release # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      release.repository.owner
    when "oauth_applications"
      app = OauthApplication.find_by_id(params[:application_id])
      # Can upload without an application ID
      return :no_target_for_conditional_access unless app # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      app.owner
    when "avatars"
      owner =
        case params[:owner_type]
        when "User"
          User.find_by_id(params[:owner_id])
        when "Team"
          team = Team.find_by_id(params[:owner_id])
          team.owner if team
        end

      return :no_target_for_conditional_access unless owner # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      owner
    when "marketplace_listing_screenshots", "marketplace_listing_images"
      listing = Marketplace::Listing.find_by_id(params[:marketplace_listing_id])
      return :no_target_for_conditional_access unless listing && listing.owner  # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      listing.owner
    when "enterprise_installation_user_accounts_uploads"
      business = Business.find_by slug: params[:business_id]
      return :no_target_for_conditional_access unless business # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      business
    else
      # Unknown model
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end

  def repository # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @repository ||= Repository.find_by(id: params[:repository_id])
  end

  def organization # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @organization ||= Organization.find_by(login: params[:org])
  end

  def gist # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @gist ||= params[:subject_type] == "Gist" ? Gist.find_by(repo_name: params[:subject]) : nil
  end

  # Private: the real reason for this method is to defer making the expensive
  # calls related to the owners plans (paid vs unpaid). By validating size
  # versus plan here on the create call, we keep the plan check off the main
  # render thread for views that may not need it.
  #
  # Returns a string we will pass over the wire to the client side JavaScript to
  # inform the user there was an error.
  def ensure_paid_account_for_oversized_videos(model)
    # Oversized videos are only supported for UserAssets that are videos.
    return unless video? && model_name == "assets"

    asset = model.new(
      size: params[:size].to_i,
      content_type: params[:content_type]
    )

    result = check_size_versus_plan(asset)
    return if result[:state] == :ok

    <<~RUBY
This video is too big. <span class="drag-and-drop-error-info">
<span class="btn-link">Try again</span> with a file size less than #{result[:limit]}.
</span>
    RUBY
  end

  # Private: check to see if the user upload video asset is to big for the
  # owner's current plan limits. This duplicates some model logic but allows us
  # to tailor the error message to the user.
  #
  # Returns a hash (essentially a tuple) of state {:ok,:error} and the limit to
  # inject into the error string where applicable.
  def check_size_versus_plan(asset)
    return { state: :ok } if asset.under_base_asset_size_limit?

    # defer this expensive check as long as possible
    owner = repository&.owner || organization || gist&.owner
    paid_upload_policy = paid_upload_policy?(owner)
    return { state: :ok } if asset.under_paid_video_size_limit_and_paying?(paid_upload_policy)
    return { state: :error, limit: "10MB" } if asset.over_base_limit_on_free_plan?(paid_upload_policy)
    return { state: :error, limit: "100MB" } if asset.over_paid_limit_on_paid_plan?(paid_upload_policy)
  end

  def track_execution_time(**kwargs)
    start_time = GitHub::Dogstats.monotonic_time
    success = yield
    elapsed = GitHub::Dogstats.duration(start_time)

    tags = kwargs.map { |k, v| "#{k}:#{v}" }
    tags.append("success:#{success}")

    GitHub.dogstats.distribution(
      "upload_policies.create.dist.time",
      elapsed,
      tags: tags
    )
  end

  def upload_policy_assets_rate_limit_filter
    model_name == "assets" || model_name == "repository-files"
  end

  def upload_policy_assets_rate_limit_key
    return "upload_policy_assets_limiter:#{current_user.id}" if model_name == "assets"
    "upload_policy_repository_files_limiter:#{current_user.id}"
  end

  def upload_policy_assets_rate_limit_log_key
    return "upload-policy-assets-#{current_user.id}" if model_name == "assets"
    "upload-policy-repository-files-#{current_user.id}"
  end

  def upload_policy_rate_limit_record
    GitHub.dogstats.increment("rate_limited", tags: ["action:#{action_name}", "controller:#{controller_name}", "model:#{model_name}"])
  end
end
