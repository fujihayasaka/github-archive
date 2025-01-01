# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-custom_copilots"
require "faraday"

class CopilotSpaceResource < ApplicationRecord::Copilot
  include ::Instrumentation::Model
  include BlackbirdIndexHelper

  self.table_name = "custom_copilot_resources"

  enum :resource_type, { unknown: 0, repository: 1, github_file: 2, free_text: 3, github_issue: 4, github_pull_request: 5, media_content: 6, uploaded_text_file: 7 }, validate: true, suffix: true

  belongs_to :copilot_space, foreign_key: :custom_copilot_id, inverse_of: :resources

  validates :copilot_space, presence: true
  validates :metadata, presence: true
  validate :validate_metadata_schema,
    :validate_repository_access
  delegate :repository_id, :repository, :text, :name, to: :parsed_metadata
  # We need the current user so we can correctly trigger indexing and cap filter to check repository access
  delegate :current_user, :cap_filter, to: :copilot_space

  # Loads the metadata from the JSON field and instantiates the correct metadata class
  def parsed_metadata
    case
    when github_file_resource_type?
      GitHubFileMetadata.from_json(metadata)
    when free_text_resource_type?
      FreeTextMetadata.from_json(metadata)
    when uploaded_text_file_resource_type?
      UploadedTextFileMetadata.from_json(metadata)
    when github_issue_resource_type?
      GitHubIssueMetadata.from_json(metadata)
    when github_pull_request_resource_type?
      GitHubPullRequestMetadata.from_json(metadata)
    when media_content_resource_type?
      MediaContentMetadata.from_json(metadata)
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
      meta = T.cast(parsed_metadata, CopilotSpaceResource::UploadedTextFileMetadata)
      return attachment&.size || 0
    when github_file_resource_type?
      repo = Repositories::Public.find_active(repository_id)
      if repo.nil?
        log_size_error("repository not found")
        return 0
      end
      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubFileMetadata)
      contents_metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repo, ref: repo.default_branch, path: meta.file_path.b)
      return contents_metadata.path_object_size || 0
    when github_issue_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubIssueMetadata)
      issue = Issue.find_by(repository_id: meta.repository_id, number: meta.number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      if issue.nil?
        log_size_error("issue not found")
        return 0
      end
      if GitHub.flipper.feature(:custom_copilots_issues_prs_comments).enabled?
        comments_size = issue.comments.sum { |comment| comment.body.bytesize } || 0
        issue_body_size = issue.body&.bytesize || 0
        return comments_size + issue_body_size
      end

      return issue.body&.bytesize || 0
    when github_pull_request_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubPullRequestMetadata)
      pull_request = Issue.includes(:pull_request).find_by(repository_id: meta.repository_id, number: meta.number)&.pull_request # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      if pull_request.nil?
        log_size_error("pull request not found")
        return 0
      end
      comments_size = 0
      if GitHub.flipper.feature(:custom_copilots_issues_prs_comments).enabled?
        comments_size += pull_request.review_comments.sum { |comment| comment.body.bytesize } || 0
        comments_size += pull_request.issue&.comments&.sum { |comment| comment.body.bytesize } || 0
        comments_size += pull_request.reviews.where.not(body: nil).sum { |review| review.body&.bytesize } || 0
      end

      pr_body_size = pull_request.body&.bytesize || 0
      diff_size = pull_request.diffs.total_byte_count || 0

      return diff_size + pr_body_size + comments_size
    when media_content_resource_type?
      meta = T.cast(parsed_metadata, CopilotSpaceResource::MediaContentMetadata)
      return meta.size || 0
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
      repo = Repositories::Public.find_active(repository_id)

      if repo.nil?
        log_file_error("repository not found")
        return false
      end

      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubFileMetadata)

      default_branch = repo.default_branch
      return false if default_branch.nil?

      file_meta_data = Repositories.domain.contents.metadata_by_ref_and_path(repository: repo, ref: default_branch, path: meta.file_path)
      return !file_meta_data.object_not_found?
    when github_issue_resource_type?
      repo = Repositories::Public.find_active(repository_id)

      if repo.nil?
        log_file_error("repository not found")
        return false
      end

      meta = T.cast(parsed_metadata, CopilotSpaceResource::GitHubIssueMetadata)

      issue = Issue.find_by(repository_id: repo.id, number: meta.number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      return !issue.nil?
    when github_pull_request_resource_type?
      repo = Repositories::Public.find_active(repository_id)

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
      # TODO: This is temporary until we have a twirp type for uploaded text files
      :free_text_metadata
    when github_issue_resource_type?
      :git_hub_issue_metadata
    when github_pull_request_resource_type?
      :git_hub_pull_request_metadata
    when media_content_resource_type?
      :media_content_metadata
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

    twirp_resource
  end

  def twirp_resource
    begin
      kwargs = {
        id: id,
        resource_type: twirp_resource_type,
      }

      kwargs[twirp_metadata_key] = parsed_metadata.to_copilot_config_twirp

      MonolithTwirp::Copilotapi::CustomCopilots::V1::Resource.new(
        **kwargs,
      )
    rescue Encoding::UndefinedConversionError => exception
      log_file_error(exception.message)
      nil
    end
  end

  def repository_based_resource?
    github_file_resource_type? || github_issue_resource_type? || github_pull_request_resource_type?
  end

  private

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
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_FREE_TEXT
    when github_issue_resource_type?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_GITHUB_ISSUE
    when github_pull_request_resource_type?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_GITHUB_PULL_REQUEST
    when media_content_resource_type?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_MEDIA_CONTENT
    else
      MonolithTwirp::Copilotapi::CustomCopilots::V1::ResourceType::RESOURCE_TYPE_INVALID
    end
  end

  def validate_metadata_schema
    case
    when github_file_resource_type?
      meta = parsed_metadata
      errors.add(:repository_id, "can't be blank") if meta.repository_id.blank?
      errors.add(:file_path, "can't be blank") if meta.file_path.blank?
    when free_text_resource_type?
      meta = parsed_metadata
      errors.add(:text, "can't be blank") if meta.text.blank?
      errors.add(:name, "can't be blank") if meta.name.blank?
    when uploaded_text_file_resource_type?
      meta = parsed_metadata
      errors.add(:name, "can't be blank") if meta.name.blank?
      errors.add(:copilot_chat_attachment_id, "can't be blank") if meta.copilot_chat_attachment_id.blank?
    when github_issue_resource_type?
      meta = parsed_metadata
      errors.add(:resource, "not found") if meta.repository_id.blank? || meta.number.blank? || meta.issue.nil?
    when github_pull_request_resource_type?
      meta = parsed_metadata
      errors.add(:resource, "not found") if meta.repository_id.blank? || meta.number.blank? || meta.pull_request.nil?
    when media_content_resource_type?
      meta = parsed_metadata
      errors.add(:name, "can't be blank") if meta.name.blank?
      errors.add(:url, "can't be blank") if meta.url.blank?
      errors.add(:media_type, "can't be blank") if meta.media_type.blank?
      errors.add(:size, "can't be blank") if meta.size.blank?
    else
      errors.add(:resource_type, "not supported")
    end
  end

  def validate_repository_access
    return unless repository_based_resource?
    return unless cap_filter # We need the cap filter to check repository access
    return if repository_id.blank?

    repository = Repository.find_by(id: repository_id)

    if repository.nil?
      errors.add(:repository, "not found")
      return
    end

    if T.must(copilot_space).owner.is_a?(Organization) && repository.owner != T.must(copilot_space).owner
      errors.add(:repository, "not found")
      return
    end

    is_readable_by_user = repository.readable_by?(current_user)
    is_cap_filter_authorized = cap_filter.unauthorized([repository]).empty?
    is_authorized_repo = is_readable_by_user && is_cap_filter_authorized

    errors.add(:repository, "not found") unless is_authorized_repo
  end

  sig { returns(T.nilable(Copilot::ChatAttachment)) }
  def attachment
    return nil unless uploaded_text_file_resource_type?

    meta = T.cast(parsed_metadata, CopilotSpaceResource::UploadedTextFileMetadata)
    attachment_id = meta.copilot_chat_attachment_id

    # Use cache if available
    @attachment_cache ||= {}
    return @attachment_cache[attachment_id] if @attachment_cache.key?(attachment_id)

    # Otherwise, fetch and cache
    @attachment_cache[attachment_id] = meta.attachment
  end

  class GitHubFileMetadata
    attr_reader :repository_id, :repository, :file_path

    sig { params(json: T.untyped).returns(T.attached_class) }
    def self.from_json(json)
      new(
        repository_id: json["repository_id"],
        file_path: json["file_path"],
      )
    end

    def initialize(repository_id:, file_path:)
      @repository_id = repository_id
      @file_path = file_path
      if @repository_id.present?
        @repository = Repositories::Public.find_active(@repository_id)
      end
    end

    def to_copilot_config_twirp
      return unless repository

      commit_oid = repository.default_oid

      blob = repository.blob(commit_oid, file_path, { truncate: false, limit: 128.kilobytes })

      # TODO: temporary rescue data to prevent space from erroring out
      # https://github.com/github/copilot-productivity/issues/5189#issuecomment-2819431033
      MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubFileMetadata.new(
        owner: repository.owner_display_login,
        name: repository.name,
        ref: repository.default_branch, # For now we don't let the user pick the ref for the file
        path: file_path,
        sha: commit_oid,
        contents: blob&.data,
        repo_id: repository.id,
        commit_oid: commit_oid
      )
    end
  end

  class FreeTextMetadata
    attr_reader :text, :name

    sig { params(json: T.untyped).returns(T.attached_class) }
    def self.from_json(json)
      new(
        text: json["text"],
        name: json["name"]
      )
    end

    def initialize(text:, name:)
      @text = text
      @name = name
    end

    def to_copilot_config_twirp
      MonolithTwirp::Copilotapi::CustomCopilots::V1::FreeTextMetadata.new(
        contents: text,
      )
    end
  end

  class GitHubIssueMetadata
    attr_reader :repository_id, :repository, :number, :issue

    sig { params(json: T.untyped).returns(T.attached_class) }
    def self.from_json(json)
      new(
        repository_id: json["repository_id"],
        number: json["number"],
      )
    end

    def initialize(repository_id:, number:)
      @repository_id = repository_id
      @number = number
      if @number.present? && @repository_id.present?
        @repository = Repositories::Public.find_active(@repository_id)
        @issue = Issue.find_by(repository_id: @repository_id, number: @number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
    end

    def to_copilot_config_twirp
      return unless issue

      comments = []
      if GitHub.flipper.feature(:custom_copilots_issues_prs_comments).enabled?
        comments = issue.comments.map do |comment|
          {
            author: comment.user.display_login,
            contents: comment.body,
            url: comment.url,
            created_at: Google::Protobuf::Timestamp.new(seconds: comment.created_at.to_i),
          }
        end
      end

      MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubIssueMetadata.new(
        owner: repository.owner_display_login,
        name: repository.name,
        number: number,
        contents: issue.body,
        title: issue.title,
        repo_id: repository.id,
        author: issue.user.display_login,
        url: issue.url,
        id: issue.id,
        comments: comments,
      )
    end

    def to_url_validation_payload
      {
        type: "github_issue",
        number: number,
        url: issue.url,
        nwo: repository.name_with_display_owner,
        title: issue.title,
        repositoryId: repository.id,
      }
    end
  end

  class GitHubPullRequestMetadata
    attr_reader :repository_id, :repository, :number, :pull_request

    sig { params(json: T.untyped).returns(T.attached_class) }
    def self.from_json(json)
      new(
        repository_id: json["repository_id"],
        number: json["number"],
      )
    end

    def initialize(repository_id:, number:)
      @repository_id = repository_id
      @number = number
      if @number.present? && repository_id.present?
        @repository = Repositories::Public.find_active(@repository_id)

        issue = Issue.includes(:pull_request).find_by(repository_id: @repository_id, number: @number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        @pull_request = issue.pull_request if issue
        @title = @pull_request.title if @pull_request
      end
    end

    def to_copilot_config_twirp
      return unless pull_request

      diffs = pull_request.diffs.map do |diff_entry|
        {
          sha: diff_entry.b_blob || diff_entry.a_blob,
          file_name: diff_entry.path,
          status: diff_entry.status_label,
          additions: diff_entry.additions,
          deletions: diff_entry.deletions,
          changes: diff_entry.changes,
          patch: diff_entry.text.try(:length).to_i > 0 && !diff_entry.binary_text? ? diff_entry.unicode_text : nil,
          previous_filename: diff_entry.renamed? ? diff_entry.a_path : nil,
        }
      end

      comments = []
      review_comments = []
      if GitHub.flipper.feature(:custom_copilots_issues_prs_comments).enabled?
        # Code level thread comments
        threads = pull_request.review_threads.to_a
        review_comments = threads.flat_map do |thread|
          thread.comments.map do |comment|
            {
              comment: {
                author: comment.user.display_login,
                contents: comment.body,
                url: comment.url,
                created_at: Google::Protobuf::Timestamp.new(seconds: comment.created_at.to_i),
              },
              file_path: thread.path,
            }
          end
        end

        # Comments on the pull request itself
        issue_comments = pull_request.issue.comments.includes(:user).map do |comment|
          {
            author: comment.user.display_login,
            contents: comment.body,
            url: comment.url,
            created_at: Google::Protobuf::Timestamp.new(seconds: comment.created_at.to_i),
          }
        end
        # Comments made when submitting a PR review
        reviews_with_body = pull_request.reviews.includes(:user).where.not(body: nil).map do |review|
          {
            author: review.user.display_login,
            contents: review.body,
            url: review.url,
            created_at: Google::Protobuf::Timestamp.new(seconds: review.created_at.to_i),
          }
        end

        comments = (issue_comments + reviews_with_body).sort_by { |comment| comment[:created_at].seconds }
      end

      MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubPullRequestMetadata.new(
        owner: repository.owner_display_login,
        name: repository.name,
        number: number,
        title: pull_request.title,
        contents: pull_request.body,
        repo_id: repository.id,
        author: pull_request.user.display_login,
        base_ref: pull_request.base_ref,
        head_ref: pull_request.head_ref,
        state: pull_request.state,
        additions: pull_request.additions,
        deletions: pull_request.deletions,
        diff_entries: diffs,
        url: pull_request.url,
        id: pull_request.id,
        comments: comments,
        review_comments: review_comments,
      )
    end

    def to_url_validation_payload
      {
        type: "github_pull_request",
        number: number,
        url: pull_request.url,
        nwo: repository.name_with_display_owner,
        title: pull_request.title,
        repositoryId: repository.id,
      }
    end
  end

  class UploadedTextFileMetadata
    include GitHub::Memoizer

    private_class_method :new
    sig { returns(String) }; attr_reader :name
    sig { returns(Integer) }; attr_reader :copilot_chat_attachment_id

    sig { params(json: T.untyped).returns(T.attached_class) }
    def self.from_json(json)
      new(
        name: json["name"],
        copilot_chat_attachment_id: json["copilot_chat_attachment_id"],
      )
    end

    sig { params(name: String, copilot_chat_attachment_id: Integer).void }
    def initialize(name:, copilot_chat_attachment_id:)
      @name = name
      @copilot_chat_attachment_id = copilot_chat_attachment_id
    end

    sig { returns(T.nilable(Copilot::ChatAttachment)) }
    memoize def attachment
      Copilot::ChatAttachment.find_by(id: copilot_chat_attachment_id)
    end

    sig { returns(MonolithTwirp::Copilotapi::CustomCopilots::V1::FreeTextMetadata) }
    def to_copilot_config_twirp
      att = attachment
      contents = nil
      if att&.uploaded?
        begin
          # Once we have a new twirp type for uploaded text files (https://github.com/github/copilot-productivity/issues/5973),
          # we will instead send the download URL to CAPI and download the file there instead of fetching the contents here.
          url = att.storage_policy.download_url
          response = GitHub::FaradayClient.external("AzureBlobStorage", url).get
          contents = response.body
        rescue => e # rubocop:disable Lint/GenericRescue
          contents = "Error downloading file, #{att.name}"
          Failbot.report(e)
        end
      else
        contents = "Attachment not found or not uploaded"
      end

      # TODO: This is temporary until we have a twirp type for uploaded text files https://github.com/github/copilot-productivity/issues/5973
      MonolithTwirp::Copilotapi::CustomCopilots::V1::FreeTextMetadata.new(contents:)
    end
  end

  class MediaContentMetadata
    attr_reader :media_type, :name, :url, :height, :width, :size

    sig { params(json: T.untyped).returns(T.attached_class) }
    def self.from_json(json)
      new(
        name: json["name"],
        url: json["url"],
        media_type: json["media_type"],
        height: json["height"],
        width: json["width"],
        size: json["size"]
      )
    end

    def initialize(name:, url:, media_type:, height:, width:, size:)
      @name = name
      @media_type = media_type
      @height = height
      @width = width
      @url = url
      @size = size
    end

    def to_copilot_config_twirp
      MonolithTwirp::Copilotapi::CustomCopilots::V1::MediaContentMetadata.new(
       name: name,
       url: url,
       media_type: media_type,
       height: height,
       width: width,
      )
    end
  end
end
