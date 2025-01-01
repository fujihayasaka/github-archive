# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-custom_copilots"
require "faraday"

class CopilotSpaceResource < ApplicationRecord::Copilot
  include ::Instrumentation::Model
  include BlackbirdIndexHelper

  self.table_name = "custom_copilot_resources"

  sig { returns(ActiveModel::Errors) }
  def cap_validator_errors
    @cap_validator_errors ||= ActiveModel::Errors.new(self)
  end

  sig { params(cap_validator_errors: ActiveModel::Errors).void }
  attr_writer :cap_validator_errors

  after_validation :clear_cap_validator_errors

  enum :resource_type, { unknown: 0, repository: 1, github_file: 2, free_text: 3, github_issue: 4, github_pull_request: 5, media_content: 6, uploaded_text_file: 7 }, validate: true, suffix: true

  belongs_to :copilot_space, foreign_key: :custom_copilot_id, inverse_of: :resources
  belongs_to :copilot_chat_attachment,
    class_name: "::Copilot::ChatAttachment",
    foreign_key: "copilot_chat_attachment_id",
    inverse_of: :copilot_space_resources,
    optional: true

  validates :copilot_space, presence: true
  validates :metadata, presence: true
  validate :validate_metadata_schema
  validate :validate_copilot_chat_attachment_id
  validate :check_cap_validator_errors
  delegate :repository, :text, :name, :file_path, :sha, to: :parsed_metadata
  # We need the current user so we can correctly trigger indexing and cap filter to check repository access
  delegate :current_user, :cap_filter, to: :copilot_space

  after_destroy_commit :destroy_chat_attachment

  EXCLUDED_COMMENT_AUTHORS = ["github-actions[bot]"].freeze
  URL_RESOURCES = [
    CopilotSpaceResource::Constants::GITHUB_FILE,
    CopilotSpaceResource::Constants::GITHUB_ISSUE,
    CopilotSpaceResource::Constants::GITHUB_PULL_REQUEST,
  ].freeze

  # Fetch the repository ID directly from the metadata since initializing the parsed_metadata will make a
  # query to fetch the repository
  sig { returns(T.nilable(Integer)) }
  def repository_id
    metadata&.dig("repository_id")
  end

  # Returns the GUID of the copilot chat attachment if it exists
  sig { returns(T.nilable(String)) }
  def copilot_chat_attachment_guid
    copilot_chat_attachment&.guid
  end

  # Loads the metadata from the JSON field and instantiates the correct metadata class
  sig do
    returns(T.any(
      CopilotSpaceResource::GitHubFileMetadata,
      CopilotSpaceResource::FreeTextMetadata,
      CopilotSpaceResource::UploadedTextFileMetadata,
      CopilotSpaceResource::GitHubIssueMetadata,
      CopilotSpaceResource::GitHubPullRequestMetadata,
      CopilotSpaceResource::MediaContentMetadata,
      CopilotSpaceResource::RepositoryMetadata
    ))
  end
  def parsed_metadata
    case
    when github_file_resource_type?
      CopilotSpaceResource::GitHubFileMetadata.from_json(metadata)
    when free_text_resource_type?
      CopilotSpaceResource::FreeTextMetadata.from_json(metadata)
    when uploaded_text_file_resource_type?
      CopilotSpaceResource::UploadedTextFileMetadata.from_json(metadata)
    when github_issue_resource_type?
      CopilotSpaceResource::GitHubIssueMetadata.from_json(metadata)
    when github_pull_request_resource_type?
      CopilotSpaceResource::GitHubPullRequestMetadata.from_json(metadata)
    when media_content_resource_type?
      if FeatureFlag.vexi.enabled?(:copilot_spaces_duplicate, current_user, default: false) && copilot_space
        url = metadata["url"].present? ? "#{metadata["url"]}?copilot_space_id=#{T.must(copilot_space).id}" : ""
      else
        url = metadata["url"]
      end
      CopilotSpaceResource::MediaContentMetadata.from_json(metadata.merge("url" => url))
    when repository_resource_type?
      CopilotSpaceResource::RepositoryMetadata.from_json(metadata)
    else
      raise "Unknown resource type: #{resource_type}"
    end
  end

  def size
    case
    when free_text_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::FreeTextMetadata)
      return meta.text.bytesize
    when uploaded_text_file_resource_type?
      return copilot_chat_attachment&.size || 0
    when github_file_resource_type?
      # We use T.must here because we know repository_id is present for github_file_resource_type
      repo = Repositories::Public.find_active(T.must(repository_id))
      if repo.nil?
        log_size_error("repository not found")
        return 0
      end
      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubFileMetadata)
      ref = meta.sha || repo.default_branch
      contents_metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repo, ref: ref, path: meta.file_path.b)
      return contents_metadata.path_object_size || 0
    when github_issue_resource_type?
      return issue_resource_size
    when github_pull_request_resource_type?
      return pull_request_resource_size
    when media_content_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::MediaContentMetadata)

      if meta.height.nil? || meta.height <= 0 || meta.width.nil? || meta.width <= 0
        return copilot_chat_attachment&.size || 0
      end

      return MediaTokenCalculator.calculate_image_tokens(meta.width, meta.height) * CopilotSpace::BYTES_PER_TOKEN # Multiply by BYTES_PER_TOKEN as we expect bytes instead of tokens
    end
    log_size_error("resource type not supported")
    0
  end

  def size_percentage
    (size / CopilotSpace.max_content_size(current_user).to_f * 100).round(10)
  end

  def file_exists?
    case
    when github_file_resource_type?
      # We use T.must here because we know repository_id is present for github_file_resource_type
      repo = Repositories::Public.find_active(T.must(repository_id))

      if repo.nil?
        log_file_error("repository not found")
        return false
      end

      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubFileMetadata)
      ref = meta.sha || repo.default_branch
      return false if ref.nil?

      file_meta_data = Repositories.domain.contents.metadata_by_ref_and_path(repository: repo, ref: ref, path: meta.file_path)
      return !file_meta_data.object_not_found?
    when repository_resource_type?
      # We use T.must here because we know repository_id is present for repository_resource_type
      repo = Repositories::Public.find_active(T.must(repository_id))

      if repo.nil?
        log_file_error("repository not found")
        return false
      else
        return true
      end
    when github_issue_resource_type?
      # We use T.must here because we know repository_id is present for github_issue_resource_type
      repo = Repositories::Public.find_active(T.must(repository_id))

      if repo.nil?
        log_file_error("repository not found")
        return false
      end

      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubIssueMetadata)

      issue = Issue.find_by(repository_id: repo.id, number: meta.number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return !issue.nil?
    when github_pull_request_resource_type?
      # We use T.must here because we know repository_id is present for github_pull_request_resource_type
      repo = Repositories::Public.find_active(T.must(repository_id))

      if repo.nil?
        log_file_error("repository not found")
        return false
      end

      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubPullRequestMetadata)
      issue = Issue.find_by(repository_id: repo.id, number: meta.number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      if issue.nil?
        log_file_error("issue not found")
        return false
      end
      pull_request = issue.pull_request

      return !pull_request.nil?
    end
    log_file_error("resource type not supported")
    false
  end

  def restricted_hydro_file_name
    case
    when repository_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::RepositoryMetadata)
      return meta.repository_id.to_s
    when github_file_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubFileMetadata)
      return meta.file_path
    when free_text_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::FreeTextMetadata)
      return meta.name
    when uploaded_text_file_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::UploadedTextFileMetadata)
      return meta.name
    when github_issue_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubIssueMetadata)
      issue = Issue.find_by(repository_id: meta.repository_id, number: meta.number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return issue.url if issue
    when github_pull_request_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubPullRequestMetadata)
      pr = Issue.includes(:pull_request).find_by(repository: meta.repository_id, number: meta.number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return pr.url if pr
    when media_content_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::MediaContentMetadata)
      return meta.name
    end
    log_size_error("resource type not supported")
    ""
  end

  def twirp_metadata_key
    case
    when github_file_resource_type?
      :git_hub_file_metadata
    when free_text_resource_type?
      :free_text_metadata
    when uploaded_text_file_resource_type?
      :uploaded_text_file_metadata
    when github_issue_resource_type?
      :git_hub_issue_metadata
    when github_pull_request_resource_type?
      :git_hub_pull_request_metadata
    when media_content_resource_type?
      :media_content_metadata
    when repository_resource_type?
      :repository_metadata
    else
      raise "Unknown resource type: #{resource_type}"
    end
  end

  sig do
    params(
      twirp_repo_access_allowed:
      T.proc.params(
        repo: Repository
      ).returns(
        T::Boolean
      )
    ).returns(T.nilable(MonolithTwirp::Copilotapi::CustomCopilots::V1::Resource))
  end
  def to_copilot_config_twirp(&twirp_repo_access_allowed)
    case
    when repository_based_resource?
      # call the twirp_repo_access_validator with the repository
      # and return if the result is not true
      return nil unless twirp_repo_access_allowed.call(repository)
    when free_text_resource_type?
    when uploaded_text_file_resource_type?
    when media_content_resource_type?
      # We don't need to check repository access
    else
      raise "Unknown resource type: #{resource_type}"
    end

    twirp_resource(opts: {})
  end

  def twirp_resource(opts: { blob: nil, commit_oid: nil })
    begin
      kwargs = {
        id:,
        copilot_chat_attachment_guid:,
        resource_type: twirp_resource_type,
      }
      twirp_metadata = parsed_metadata.to_copilot_config_twirp(opts: { blob: opts[:blob], commit_oid: opts[:commit_oid] })

      unless twirp_metadata
        GitHub.logger.warn("Missing or invalid resource metadata", {
          "gh.copilot.copilot_space.id": copilot_space&.id,
          "gh.copilot.copilot_space.owner_id": current_user.id,
          "gh.copilot.copilot_space.resource.id": id,
          "gh.copilot.copilot_space.resource.type": resource_type,
        })
        return
      end
      kwargs[twirp_metadata_key] = twirp_metadata

      MonolithTwirp::Copilotapi::CustomCopilots::V1::Resource.new(
        **kwargs,
      )
    rescue Encoding::UndefinedConversionError => exception
      log_file_error(exception.message)
      nil
    end
  end

  def repository_based_resource?
    github_file_resource_type? || github_issue_resource_type? || github_pull_request_resource_type? || repository_resource_type?
  end

  def self.exclude_comment?(comment)
    author = comment.user
    # When using display_login for bots, this call will return integration-<some-id>[bot]
    # which causes the tests to fail when testing all features
    # rubocop:disable GitHub/DoNotAllowLogin
    author.bot? && EXCLUDED_COMMENT_AUTHORS.include?(author&.login) && comment.body.include?("Bundle Stats")
  end

  private

  # Copies errors from the CAP validation (which runs before the save transaction)
  def check_cap_validator_errors
    errors.merge!(cap_validator_errors) if cap_validator_errors.present?
  end

  def clear_cap_validator_errors
    cap_validator_errors = nil
  end

  def log_size_error(msg)
    GitHub.logger.error("custom_copilot.custom_copilot_resource.size: #{msg}", {
      "gh.copilot.custom_copilot.id": copilot_space&.id,
      "gh.copilot.custom_copilot.owner_id": current_user.id,
      "gh.copilot.custom_copilot.resource.id": id,
      "gh.copilot.custom_copilot.resource.metadata": metadata,
    })
  end

  def log_file_error(msg)
    GitHub.logger.error("custom_copilot.custom_copilot_resource.file_exists: #{msg}", {
      "gh.copilot.custom_copilot.id": copilot_space&.id,
      "gh.copilot.custom_copilot.owner_id": current_user.id,
      "gh.copilot.custom_copilot.resource.id": id,
      "gh.copilot.custom_copilot.resource.metadata": metadata,
    })
  end

  def twirp_resource_type
    case
    when github_file_resource_type?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_GITHUB_FILE
    when free_text_resource_type?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_FREE_TEXT
    when uploaded_text_file_resource_type?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_UPLOADED_TEXT_FILE
    when github_issue_resource_type?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_GITHUB_ISSUE
    when github_pull_request_resource_type?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_GITHUB_PULL_REQUEST
    when media_content_resource_type?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_MEDIA_CONTENT
    when repository_resource_type?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_REPOSITORY
    else
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_INVALID
    end
  end

  def validate_copilot_chat_attachment_id
    return errors.add(:copilot_chat_attachment_id, "cannot be changed") if copilot_chat_attachment_id_changed? && persisted?

    if copilot_chat_attachment_id.blank?
      case
      when uploaded_text_file_resource_type?
        errors.add(:copilot_chat_attachment_id, "can't be blank for uploaded text files")
      when media_content_resource_type?
        errors.add(:copilot_chat_attachment_id, "can't be blank for media content")
      end
    end

    if copilot_chat_attachment_id.present? && copilot_chat_attachment.blank?
      errors.add(:copilot_chat_attachment, "not found")
    end

    if copilot_chat_attachment.present?
      unless copilot_chat_attachment&.uploader_id == current_user.id
        errors.add(:copilot_chat_attachment, "not found")
      end
    end
  end

  def validate_metadata_schema
    case
    when github_file_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubFileMetadata)
      errors.add(:repository_id, "can't be blank") if meta.repository_id.blank?
      errors.add(:file_path, "can't be blank") if meta.file_path.blank?
    when repository_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::RepositoryMetadata)
      errors.add(:repository_id, "can't be blank") if meta.repository_id.blank?
    when free_text_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::FreeTextMetadata)
      errors.add(:text, "can't be blank") if meta.text.blank?
      errors.add(:name, "can't be blank") if meta.name.blank?
    when uploaded_text_file_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::UploadedTextFileMetadata)
      errors.add(:name, "can't be blank") if meta.name.blank?
    when github_issue_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubIssueMetadata)
      errors.add(:resource, "not found") if meta.repository_id.blank? || meta.number.blank? || meta.issue.nil?
    when github_pull_request_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubPullRequestMetadata)
      errors.add(:resource, "not found") if meta.repository_id.blank? || meta.number.blank? || meta.pull_request.nil?
    when media_content_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::MediaContentMetadata)
      errors.add(:name, "can't be blank") if meta.name.blank?
      errors.add(:url, "can't be blank") if meta.url.blank?
      errors.add(:media_type, "can't be blank") if meta.media_type.blank?
    else
      errors.add(:resource_type, "not supported")
    end
  end

  def destroy_chat_attachment
    # Only delete the chat attachment if there are no longer any resources associated with it
    if copilot_chat_attachment&.reload&.copilot_space_resources&.none?
      copilot_chat_attachment&.destroy
    end
  end

  def pull_request_resource_size
    meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubPullRequestMetadata)
    issue = Issue.includes(:pull_request).find_by(repository_id: meta.repository_id, number: meta.number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    pull_request = issue&.pull_request

    if pull_request.nil? || issue.nil?
      log_size_error("pull request not found")
      return 0
    end

    comments_size = 0
    comments_size += pull_request.review_comments.sum { |comment| comment.body.bytesize } || 0
    issue_comments = issue.comments.filter { |comment| !(CopilotSpaceResource.exclude_comment?(comment)) }
    comments_size += issue_comments.sum { |comment| comment.body.bytesize } || 0
    comments_size += pull_request.reviews.where.not(body: nil).sum { |review| review.body&.bytesize } || 0

    pr_body_size = pull_request.body&.bytesize || 0
    diff_size = pull_request.diffs.total_byte_count || 0

    diff_size + pr_body_size + comments_size
  end

  def issue_resource_size
    meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubIssueMetadata)
    issue = Issue.find_by(repository_id: meta.repository_id, number: meta.number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    if issue.nil?
      log_size_error("issue not found")
      return 0
    end
    comments_size = issue.comments.sum { |comment| comment.body.bytesize } || 0
    issue_body_size = issue.body&.bytesize || 0
    comments_size + issue_body_size
  end
end
