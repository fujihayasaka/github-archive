# typed: true
# frozen_string_literal: true

class CopilotSpace < ApplicationRecord::Copilot
  include CopilotSpaces::AuthorizationHelper

  include ::Instrumentation::Model
  include CopilotSpace::PermissionsDependency
  include CopilotSpace::StarsDependency

  include Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = Permissions::Attributes::CopilotSpace
  include CopilotSpace::SequenceDependency

  self.table_name = "custom_copilots"

  enum :visibility, { private: 0, org_public: 1 }, validate: true, suffix: true, default: :private

  # 350 matches repositories. Keeps this distinct from system instructions and limits use to descriptions.
  MAX_DESCRIPTION_LENGTH = 350
  MAX_GENERAL_INSTRUCTIONS_LENGTH = 4000

  # The token limit is 96k tokens, 3/4ths of the total 128k token context window.
  # The original 48k token limit is still in place for users who do not have the feature flag.
  # For now, we're using an estimate of 3 bytes per token until we get actual token counting.
  # Does not include general instructions, it is too small to affect our validations.
  # Important! if you update this, make sure to update in ui/packages/copilot-immersive-v1/components/Spaces/TextFileDialog.tsx
  sig { params(viewer: T.nilable(User)).returns(Integer) }
  def self.max_content_size(viewer)
    if viewer&.feature_enabled?(:custom_copilots_128k_window)
      96_000 * 3 # 75% of 128k tokens
    else
      48_000 * 3 # 75% of 64k tokens
    end
  end

  # The default icon type and color for custom copilots

  DEFAULT_ICON_TYPE = "DependabotIcon"
  DEFAULT_ICON_COLOR = "blue"

  attr_accessor :current_user, :cap_filter

  belongs_to :owner, polymorphic: true, strict_loading: false
  belongs_to :creator, class_name: "User", optional: true

  has_many :resources, foreign_key: "custom_copilot_id", class_name: "CopilotSpaceResource", inverse_of: :copilot_space
  has_many :user_roles, -> { where("target_type" => "CustomCopilot") },
    as: :target, class_name: "UserRole"

  destroy_dependents_in_background :resources
  destroy_dependents_in_background :user_roles

  accepts_nested_attributes_for :resources, allow_destroy: true, reject_if: :all_blank

  validates :owner, presence: true
  validates :name, length: { maximum: 255 }, presence: true, uniqueness: { scope: :owner, case_sensitive: false }
  validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }
  validates :icon_url, length: { maximum: 1000 }, allow_nil: true
  validates :general_instructions, length: { maximum: MAX_GENERAL_INSTRUCTIONS_LENGTH }, allow_nil: true
  validates :slug, length: { maximum: 255 }, presence: true, uniqueness: { scope: :owner, case_sensitive: false }
  validates :creator, presence: true, on: :create

  validates :number, presence: true, numericality: { only_integer: true, greater_than: 0 }, on: :create
  validates :number, uniqueness: { scope: [:owner_type, :owner_id] }, on: :create

  validate :validate_total_content_size
  validate :validate_visibility, if: lambda { |c| c.owner.present? }
  validate :validate_owner, on: :create, if: lambda { |c| c.owner.present? }

  before_validation :generate_slug, if: :name_changed?
  before_validation :generate_uuid, on: :create
  before_validation :generate_icon, on: :create
  before_validation :set_number, on: :create

  def self.for_uuid(uuid)
    find_by(uuid: uuid)
  end

  sig { params(login: String, number: T.any(Integer, String)).returns(CopilotSpace) }
  def self.for_owner_login_and_number!(login, number)
    owner = User.find_by_login(login)
    raise ActiveRecord::RecordNotFound unless owner
    CopilotSpace.find_by!(owner: owner, number: number)
  end

  sig { params(viewer: User, cap_filter: ConditionalAccess::Web::Filter).returns(T::Array[T.untyped]) }
  def resources_react_payload(viewer:, cap_filter:)
    github_resources = if viewer.feature_enabled?(:custom_copilots_issues_prs)
      github_resources_react_payload(viewer:, cap_filter:)
    else
      github_file_resources_react_payload(viewer:, cap_filter:)
    end

    [].concat(
      github_resources,
      free_text_resources_react_payload,
      uploaded_text_file_resources_react_payload(viewer:),
      media_content_resources_react_payload(viewer:)
    )
  end

  sig { params(viewer: User, cap_filter: ConditionalAccess::Web::Filter).returns(T::Array[T.untyped]) }
  def github_file_resources_react_payload(viewer:, cap_filter:)
    # Will return a hash where the key is the repository id and the value is the Repository
    visible_repos_indexed_by_id = authorized_repositories(github_file_resources.map(&:repository_id), viewer:, cap_filter:).index_by(&:id)

    # Remove resources that are not visible to the user
    readable_resources = github_file_resources.select do |resource|
      visible_repos_indexed_by_id.key?(resource.repository_id)
    end

    readable_resources.map do |resource|
      meta = T.cast(resource.parsed_metadata, CopilotSpaceResource::GitHubFileMetadata)
      repo = visible_repos_indexed_by_id.fetch(resource.repository_id)

      {
        # The 'id' is used by the DataTable component on the frontend. For persisted records like these we use the database id.
        id: resource.id.to_s,
        databaseId: resource.id,
        repositoryId: repo.id,
        nwo: repo.name_with_display_owner,
        filePath: meta.file_path,
        sizePercentage: resource.size_percentage,
        markedForDestroy: false,
        fileExists: resource.file_exists?,
        type: "github_file",
        commitish: repo.default_branch,
      }
    end
  end

  sig { params(viewer: User, cap_filter: ConditionalAccess::Web::Filter).returns(T::Array[T.untyped]) }
  def github_resources_react_payload(viewer:, cap_filter:)
    # Will return a hash where the key is the repository id and the value is the Repository
    visible_repos_indexed_by_id = authorized_repositories(github_resources_for_repos.map(&:repository_id), viewer:, cap_filter:).index_by(&:id)

    # Remove resources that are not visible to the user
    readable_resources = github_resources_for_repos.select do |resource|
      visible_repos_indexed_by_id.key?(resource.repository_id)
    end

    readable_resources.map do |resource|
      repo = visible_repos_indexed_by_id.fetch(resource.repository_id)

      case resource.resource_type
      when "github_file"
        meta = T.cast(resource.parsed_metadata, CopilotSpaceResource::GitHubFileMetadata)

        {
          # The 'id' is used by the DataTable component on the frontend. For persisted records like these we use the database id.
          id: resource.id.to_s,
          databaseId: resource.id,
          repositoryId: repo.id,
          nwo: repo.name_with_display_owner,
          filePath: meta.file_path,
          sizePercentage: resource.size_percentage,
          markedForDestroy: false,
          fileExists: resource.file_exists?,
          type: resource.resource_type,
          commitish: repo.default_branch,
        }
      when "github_issue"
        meta = T.cast(resource.parsed_metadata, CopilotSpaceResource::GitHubIssueMetadata)
        issue = Issue.find_by(repository: repo, number: meta.number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        # If the issue is not found, we don't want to show it in the list
        next if issue.nil?

        {
          # The 'id' is used by the DataTable component on the frontend. For persisted records like these we use the database id.
          id: resource.id.to_s,
          databaseId: resource.id,
          repositoryId: repo.id,
          nwo: repo.name_with_display_owner,
          number: meta.number,
          sizePercentage: resource.size_percentage,
          markedForDestroy: false,
          type: resource.resource_type,
          title: issue.title,
          url: issue.url,
        }
      when "github_pull_request"
        meta = T.cast(resource.parsed_metadata, CopilotSpaceResource::GitHubPullRequestMetadata)
        pull_request = Issue.includes(:pull_request).find_by(repository: repo, number: meta.number) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        # If the issue is not found, we don't want to show it in the list
        next if pull_request.nil?

        {
          # The 'id' is used by the DataTable component on the frontend. For persisted records like these we use the database id.
          id: resource.id.to_s,
          databaseId: resource.id,
          repositoryId: repo.id,
          nwo: repo.name_with_display_owner,
          number: meta.number,
          sizePercentage: resource.size_percentage,
          markedForDestroy: false,
          type: resource.resource_type,
          title: pull_request.title,
          url: pull_request.url,
        }
      end
    end.compact
  end

  sig { returns(T::Array[User]) }
  def orgs
    repos_in_copilot_space_ids = resources.select { |resource| resource.resource_type == "github_file" }.map(&:repository_id)
    return [] if repos_in_copilot_space_ids.empty?
    repos_in_copilot_space = Repository.where(id: repos_in_copilot_space_ids)
    repos_in_copilot_space.map(&:owner).compact.select { |org| org.is_a?(Organization) }
  end

  # organizations that own at least one repo in the custom copilot but that the current user is not single-signed-on to
  sig { params(cap_filter: T.untyped).returns(T::Array[String]) }
  def protected_organizations(cap_filter:)
    cap_filter.unauthorized_resources(orgs).pluck(:display_login)
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def free_text_resources_react_payload
    free_text_resources.map do |resource|
      meta = T.cast(resource.parsed_metadata, CopilotSpaceResource::FreeTextMetadata)
      {
        # The 'id' is used by the DataTable component on the frontend. For persisted records like these we use the database id.
        id: resource.id.to_s,
        databaseId: resource.id,
        text: meta.text,
        name: meta.name,
        sizePercentage: resource.size_percentage,
        markedForDestroy: false,
        type: "free_text",
      }
    end
  end

  sig { params(viewer: User).returns(T::Array[T::Hash[String, T.untyped]]) }
  def uploaded_text_file_resources_react_payload(viewer:)
    return [] unless viewer.feature_enabled?(:custom_copilots_file_uploads)

    uploaded_text_file_resources.map do |resource|
      meta = T.cast(resource.parsed_metadata, CopilotSpaceResource::UploadedTextFileMetadata)
      {
        id: resource.id.to_s,
        databaseId: resource.id,
        name: meta.name,
        copilotChatAttachmentId: meta.copilot_chat_attachment_id,
        sizePercentage: resource.size_percentage,
        markedForDestroy: false,
        type: "uploaded_text_file",
      }
    end
  end

  sig { params(viewer: User).returns(T::Array[T::Hash[String, T.untyped]]) }
  def media_content_resources_react_payload(viewer:)
    return [] unless viewer.feature_enabled?(:copilot_custom_copilots_images)

    media_content_resources.map do |resource|
      meta = T.cast(resource.parsed_metadata, CopilotSpaceResource::MediaContentMetadata)
      {
        id: resource.id.to_s,
        databaseId: resource.id,
        url: meta.url,
        mediaType: meta.media_type,
        name: meta.name,
        size: meta.size,
        sizePercentage: resource.size_percentage,
        markedForDestroy: false,
        type: "media_content",
      }
    end
  end

  sig { params(repository_ids: T::Array[T.untyped], viewer: T.nilable(User), cap_filter: T.untyped).returns(T::Array[Repository]) }
  def authorized_repositories(repository_ids, viewer:, cap_filter:)
    repos = Repositories::Public.load_repositories(repository_ids)

    # We need to check readability and cap filter. Docs for CAP: https://thehub.github.com/epd/engineering/products-and-services/dotcom/cap/cookbook/
    cap_filter.authorized(repos).results.map(&:resource).filter do |repo|
      repo.readable_by?(viewer)
    end
  end

  def generate_slug
    return unless name.present?
    self.slug = name.parameterize
  end

  def slug_with_owner
    "#{owner.display_login}/#{slug}"
  end

  def twirp_owner_type
    if owner.organization?
      MonolithTwirp::Copilotapi::CustomCopilots::V1::OwnerType::OWNER_TYPE_ORG
    else
      MonolithTwirp::Copilotapi::CustomCopilots::V1::OwnerType::OWNER_TYPE_USER
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
    ).returns(MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfig)
  end
  def to_copilot_config_twirp(&twirp_repo_access_allowed)
    MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfig.new(
      description: description,
      general_instructions: general_instructions,
      id: id,
      name: name,
      owner_id: owner_id,
      owner_type: twirp_owner_type,
      owner_login: owner.display_login,
      resources: resources.map { |resource| resource.to_copilot_config_twirp(&twirp_repo_access_allowed) }.compact,
      slug: slug,
      number: number,
    )
  end

  def size_percentage
    (total_content_size / CopilotSpace.max_content_size(current_user).to_f * 100).round(10)
  end

  def total_content_size
    # Remove resources that are marked for destruction
    pending_resources = resources.select do |resource|
      !resource.marked_for_destruction?
    end

    # Split resources into github resources and other resources
    github_resources, other_resources = pending_resources.partition do |resource|
      resource.resource_type.to_sym == :github_file || resource.resource_type.to_sym == :github_issue || resource.resource_type.to_sym == :github_pull_request
    end

    # Will return a hash where the key is the repository id and the value is the Repository
    visible_repos_indexed_by_id = authorized_repositories(github_resources.map(&:repository_id), viewer: current_user, cap_filter:).index_by(&:id)

    readable_github_resources = github_resources.select do |resource|
      visible_repos_indexed_by_id.key?(resource.repository_id)
    end

    # Add size of github resources
    total_size = readable_github_resources.sum do |resource|
      resource.size.to_i # Ensure nil size returns 0
    end

    # Add size of other resources
    total_size += other_resources.sum do |resource|
      resource.size
    end
  end

  def total_content_size_exceeds_limit?
    total_content_size > CopilotSpace.max_content_size(current_user)
  end

  def user_role_target_type
    "CustomCopilot"
  end

  def target_for_conditional_access
    owner
  end

  def is_enterprise_managed?
    owner = self.owner
    case owner
    when Organization
      owner.enterprise_managed_user_enabled?
    when User
      owner.is_enterprise_managed?
    else
      false
    end
  end

  private

  sig { returns(T.nilable(Integer)) }
  def set_number
    return if self.number
    return unless owner

    create_sequence_if_missing
    self.number = Sequence.next(self)
  end

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def generate_icon
    self.icon_type = DEFAULT_ICON_TYPE if icon_type.blank?
    self.icon_color = DEFAULT_ICON_COLOR if icon_color.blank?
  end

  def validate_total_content_size
    if total_content_size_exceeds_limit?
      errors.add(:base, "The size of the space exceeds the current limit. Please remove a resource and try again.")
    end
  end

  def validate_visibility
    if !owner.organization? && !private_visibility?
      errors.add(:base, "Only organization owned spaces can be shared.")
    end
  end

  def validate_owner
    if owner.user?
      if owner.id != current_user.id
        errors.add(:base, "Unable to create a space for this user.")
      end
    elsif owner.organization?
      authorized_orgs = CopilotSpaces::AuthorizationHelper.authorized_orgs_with_copilot_access(current_user, cap_filter)

      if !authorized_orgs.find { |org| org.id == owner.id }.present?
        errors.add(:base, "Unable to create a space for this organization.")
      end
    else
      errors.add(:base, "The owner is invalid.")
    end
  end

  def free_text_resources
    resources.where(resource_type: :free_text)
  end

  def uploaded_text_file_resources
    resources.where(resource_type: :uploaded_text_file)
  end

  def github_file_resources
    resources.where(resource_type: :github_file)
  end

  def github_issue_resources
    resources.where(resource_type: :github_issue)
  end

  def github_pull_request_resources
    resources.where(resource_type: :github_pull_request)
  end

  def github_resources_for_repos
    github_file_resources + github_issue_resources + github_pull_request_resources
  end

  def media_content_resources
    resources.where(resource_type: :media_content)
  end
end
