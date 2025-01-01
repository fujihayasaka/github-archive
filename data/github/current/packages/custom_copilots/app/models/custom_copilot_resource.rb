# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilotapi-custom_copilots"

class CustomCopilotResource < ApplicationRecord::Copilot
  include ::Instrumentation::Model
  include BlackbirdIndexHelper

  FREE_TEXT_CHAR_LIMIT = 20_000

  self.table_name = "custom_copilot_resources"

  enum :resource_type, { unknown: 0, repository: 1, github_file: 2, free_text: 3 }, validate: true, suffix: true

  belongs_to :custom_copilot, inverse_of: :resources

  validates :custom_copilot, presence: true
  validates :metadata, presence: true
  validate :validate_metadata_schema,
    :validate_repository_access
  delegate :repository_id, :repository, :text, :name, to: :parsed_metadata
  # We need the current user so we can correctly trigger indexing and cap filter to check repository access
  delegate :current_user, :cap_filter, to: :custom_copilot

  # Loads the metadata from the JSON field and instantiates the correct metadata class
  def parsed_metadata
    case
    when github_file_resource_type?
      GitHubFileMetadata.from_json(metadata)
    when free_text_resource_type?
      FreeTextMetadata.from_json(metadata)
    else
      raise "Unknown resource type: #{resource_type}"
    end
  end

  def size
    case
    when free_text_resource_type?
      meta = T.cast(parsed_metadata, CustomCopilotResource::FreeTextMetadata)
      return meta.text.bytesize
    when github_file_resource_type?
      repo = Repositories::Public.find_active(repository_id)
      if repo.nil?
        log_size_error("repository not found")
        return 0
      end
      meta = T.cast(parsed_metadata, CustomCopilotResource::GitHubFileMetadata)
      contents_metadata = Repositories.domain.contents.metadata_by_ref_and_path(repository: repo, ref: repo.default_branch, path: meta.file_path)
      return contents_metadata.path_object_size
    end
    log_size_error("resource type not supported")
    0
  end

  def file_name
    case
    when github_file_resource_type?
      meta = T.cast(parsed_metadata, CustomCopilotResource::GitHubFileMetadata)
      return meta.file_path
    when free_text_resource_type?
      meta = T.cast(parsed_metadata, CustomCopilotResource::FreeTextMetadata)
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
    else
      raise "Unknown resource type: #{resource_type}"
    end
  end

  def to_copilot_config_twirp
    kwargs = {
      id: id,
      resource_type: twirp_resource_type,
    }

    kwargs[twirp_metadata_key] = parsed_metadata.to_copilot_config_twirp

    MonolithTwirp::Copilotapi::CustomCopilots::V1::Resource.new(
      **kwargs,
    )
  end

  private

  def log_size_error(msg)
    GitHub.logger.error("custom_copilot.custom_copilot_resource.size: #{msg}", {
      "gh.copilot.custom_copilot.id": custom_copilot&.id,
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
      errors.add(:text, "is too long") if meta.text.length > FREE_TEXT_CHAR_LIMIT
      errors.add(:name, "can't be blank") if meta.name.blank?
    end
  end

  def validate_repository_access
    return unless github_file_resource_type? # We only need to validate repository access for repository resources
    return unless cap_filter # We need the cap filter to check repository access
    return if repository_id.blank?

    repository = Repository.find_by(id: repository_id)

    if repository.nil?
      errors.add(:repository, "not found")
      return
    end

    is_readable_by_user = repository.readable_by?(current_user)
    is_cap_filter_authorized = cap_filter.unauthorized([repository]).empty?
    is_authorized_repo = is_readable_by_user && is_cap_filter_authorized

    errors.add(:repository, "not found") unless is_authorized_repo
  end

  class GitHubFileMetadata
    attr_reader :repository_id, :repository, :file_path

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
      MonolithTwirp::Copilotapi::CustomCopilots::V1::GitHubFileMetadata.new(
        owner: repository.owner_display_login,
        name: repository.name,
        ref: repository.default_branch, # For now we don't let the user pick the ref for the file
        path: file_path,
        sha: commit_oid,
        contents: blob&.data
      )
    end
  end

  class FreeTextMetadata
    attr_reader :text, :name

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
end
