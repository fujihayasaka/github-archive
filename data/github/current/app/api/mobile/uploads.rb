# typed: true
# frozen_string_literal: true

# Endpoints to support uploads from the mobile clients. Makes use of Alambic
# very much like UploadPoliciesController and UploadsController.
#
#   1. POST to /mobile/upload/policies
#        to create the policy document validating the file upload.
#   2. POST the file to be uploaded to the endpoint specified in the policy
#   3. PUT to asset_upload_url (returned in the POST in step 1)
#        to signal that the file upload completed successfully.
#
class Api::Mobile::Uploads < Api::App
  include UploadHelper

  PAID_UPLOAD_POLICY_ERROR_MESSAGE = "file smaller than 10MB or a video smaller than 100MB."
  FREE_UPLOAD_POLICY_ERROR_MESSAGE = "file smaller than 10MB."

  post "/mobile/upload/policy", operation_id: :unreleased do
    @route_owner = "@github/pe-mobile"
    # This is intentionally not released to the general API population
    control_access :mobile_assets_write_asset,
      resource: Platform::PublicResource.new(resource: current_user),
      allow_integrations: false,
      allow_user_via_granular_actor: false

    data = receive_with_schema("mobile-upload", "policy")
    content_type = data["content_type"]
    repo = repository(data)

    # Explicitly add :repository_id, in case request only contains :subject_id.
    # Storage policies and policy creators expect data to include this key explicitly.
    data["repository_id"] ||= repo&.id

    model_name = "assets"
    if repo && !media?(content_type)
      model_name = "repository-files"
    end

    if video?(content_type) && !videos_enabled?(repo)
      deliver_error! 422, message: "Invalid content type"
    end

    if svg?(content_type)
      deliver_error! 422, message: "Invalid content type"
    end

    size = data["size"].to_i
    if size_exceeds_limit?(content_type, size, model_name, repo)
      deliver_error! 422,
        message: "Upload size is too large",
        errors: [api_error(:MobileAssetUpload, :size, :too_large, message: "Try again with a #{configured_upload_policy_error_message(repo)}")]
    end

    uploader = ::Storage.policy_creator.for(model_name)

    ActiveRecord::Base.connected_to(role: :writing) do
      policy = if GitHub.storage_cluster_enabled?
        create_with_storage_policy(uploader.model, data)
      else
        uploader.create(current_user, data)
      end
      deliver_policy(policy, model_name)
    end
  end

  put "/mobile/upload/assets/:asset_id", operation_id: :unreleased do
    @route_owner = "@github/pe-mobile"
    # This is intentionally not released to the general API population
    control_access :mobile_assets_write_asset,
      resource: Platform::PublicResource.new(resource: current_user),
      allow_integrations: false,
      allow_user_via_granular_actor: false

    _ = receive_with_schema("mobile-upload", "complete-user-asset")

    current_asset = UserAsset.find_by(id: params["asset_id"], user_id: current_user.id)

    deliver_error! 404, message: "Invalid asset" unless current_asset.present?

    deliver_response current_asset
  end

  put "/mobile/upload/repository-files/:file_id", operation_id: :unreleased do
    @route_owner = "@github/pe-mobile"
    # This is intentionally not released to the general API population
    control_access :mobile_assets_write_asset,
      resource: Platform::PublicResource.new(resource: current_user),
      allow_integrations: false,
      allow_user_via_granular_actor: false

    _ = receive_with_schema("mobile-upload", "complete-repo-file")

    current_asset = RepositoryFile.where(id: params["file_id"], uploader_id: current_user.id).first

    deliver_error! 404, message: "Invalid repository file" unless current_asset.present?

    if !current_asset.upload_access_allowed?(current_user)
      deliver_error! 404, message: "Access not allowed"
    end

    deliver_response current_asset
  end

  private

  def media?(content_type)
    ::Storage::Uploadable::CONTENT_TYPES[:media].include?(content_type)
  end

  def svg?(content_type)
    ::Storage::Uploadable::SVG_CONTENT_TYPE.include?(content_type)
  end

  def video?(content_type)
    ::Storage::Uploadable::VIDEO_CONTENT_TYPES.include?(content_type)
  end

  # Valid types that could be commented on, and as such, have assets uploaded to.
  VALID_SUBJECT_TYPES = %w(
    CommitComment
    Discussion
    DiscussionComment
    Issue
    IssueComment
    PullRequest
    PullRequestReview
    PullRequestReviewThread
    PullRequestReviewComment
    RepositoryAdvisory
    RepositoryAdvisoryComment
    Repository
  ).to_set.freeze

  # Repository to which asset could be associated with, should one exist for the
  # given parameters.
  def repository(data)
    if repo_id = data["repository_id"]
      return Repository.find_by(id: repo_id)
    end

    if node_id = data["subject_id"]
      type, id = Platform::Helpers::NodeIdentification.from_global_id(node_id)
      return unless VALID_SUBJECT_TYPES.include?(type)
      case type
      when "Repository"
        Repository.find_by(id: id)
      when "RepositoryAdvisory"
        # `RepositoryAdvisory`s use a non-database ID for it's global ID
        subject = RepositoryAdvisory.find_by(ghsa_id: id)
        subject.try(:repository)
      else
        subject = type.safe_constantize&.find_by(id: id)
        subject.try(:repository)
      end
    end
  end

  def videos_enabled?(repo)
    # currently only enabled where the repository is non-nil. setting this to
    # `true` will cause some tests to fail, which we can investigate in a
    # follow-up PR
    repo
  end

  def size_exceeds_limit?(content_type, size, model_name, repository)
    # Oversized file size error messages are only supported for UserAssets.
    return false unless model_name == "assets"

    owner = repository&.owner
    if video?(content_type) && paid_upload_policy?(owner)
      size > UserAsset::VIDEO_PAID_SIZE_LIMIT
    else
      size > UserAsset::ASSET_SIZE_LIMIT
    end
  end

  def configured_upload_policy_error_message(repo)
    return FREE_UPLOAD_POLICY_ERROR_MESSAGE unless videos_enabled?(repo)

    owner = repo&.owner

    paid_upload_policy?(owner) ? PAID_UPLOAD_POLICY_ERROR_MESSAGE : FREE_UPLOAD_POLICY_ERROR_MESSAGE
  end

  def create_with_storage_policy(uploadable_class, data)
    meta = {}
    uploadable_class.uploadable_policy_attributes.each do |key|
      meta[key] = data[key.to_s]
    end

    blob = ::Storage::Blob.new(size: meta[:size])

    uploadable_class.storage_new(current_user, blob, meta)
  end

  def deliver_policy(uploadable, model_name)
    if uploadable.valid?
      policy = uploadable.storage_policy(actor: current_user)
      deliver! :mobile_policy_hash, policy, url: "/mobile/upload/#{model_name}/#{uploadable.id}", status: 201
    end

    extra = {
      model_name: uploadable.class.name,
    }

    # Removed the extra messsages,  as a few of
    # these errors looked like they had usernames.
    # See RepositoryImage#uploader_access for an example.

    err = StandardError.new("Failed to create #{uploadable.class.name}")
    Failbot.report_user_error(err, extra)

    deliver_error! 422, errors: uploadable.errors
  end

  def deliver_response(asset)
    if asset.track_uploaded
      deliver :mobile_asset_hash, asset.storage_policy, status: 200
    else
      deliver_error! 400, errors: asset.errors.full_messages
    end
  end
end
