# typed: true
# frozen_string_literal: true

class CustomCopilot < ApplicationRecord::Copilot
  include ::Instrumentation::Model

  self.table_name = "custom_copilots"

  MAX_GENERAL_INSTRUCTIONS_LENGTH = 2000

  # The interim token limit is 48,000 tokens. For now, we're using an estimate of 3 bytes per token until we get actual token counting.
  MAX_CONTENT_SIZE = 48_000 * 3

  attr_accessor :current_user, :cap_filter

  belongs_to :owner, polymorphic: true, strict_loading: false
  has_many :resources, foreign_key: "custom_copilot_id", class_name: "CustomCopilotResource", inverse_of: :custom_copilot
  destroy_dependents_in_background :resources

  accepts_nested_attributes_for :resources, allow_destroy: true, reject_if: :all_blank

  validates :owner, presence: true
  validates :name, length: { maximum: 255 }, presence: true, uniqueness: { scope: :owner, case_sensitive: false }
  validates :description, length: { maximum: 1000 }
  validates :icon_url, length: { maximum: 1000 }, allow_nil: true
  validates :general_instructions, length: { maximum: MAX_GENERAL_INSTRUCTIONS_LENGTH }, allow_nil: true
  validates :slug, length: { maximum: 255 }, presence: true, uniqueness: { scope: :owner, case_sensitive: false }

  validate :validate_total_content_size

  before_validation :generate_slug, if: :name_changed?
  before_validation :generate_uuid, on: :create

  def self.for_uuid(uuid)
    find_by(uuid: uuid)
  end

  def primary_avatar_path
    return icon_url if icon_url.present?

    User.ghost.primary_avatar_url
  end

  def viewable_by?(user)
    owner == user
  end

  def editable_by?(user)
    viewable_by?(user)
  end

  sig { params(viewer: User, cap_filter: ConditionalAccess::Web::Filter).returns(T::Array[T.untyped]) }
  def resources_react_payload(viewer:, cap_filter:)
    github_file_resources_react_payload(viewer:, cap_filter:) + free_text_resources_react_payload
  end

  sig { params(viewer: User, cap_filter: ConditionalAccess::Web::Filter).returns(T::Array[T.untyped]) }
  def github_file_resources_react_payload(viewer:, cap_filter:)
    # Will return a hash where the key is the repository id and the value is the Repository
    visible_repos_indexed_by_id = authorized_repositories(github_file_resources, viewer:, cap_filter:).index_by(&:id)

    # Remove resources that are not visible to the user
    readable_resources = github_file_resources.select do |resource|
      visible_repos_indexed_by_id.key?(resource.repository_id)
    end

    readable_resources.map do |resource|
      meta = T.cast(resource.parsed_metadata, CustomCopilotResource::GitHubFileMetadata)
      repo = visible_repos_indexed_by_id.fetch(resource.repository_id)
      {
        # The 'id' is used by the DataTable component on the frontend. For persisted records like these we use the database id.
        id: resource.id.to_s,
        databaseId: resource.id,
        repositoryId: repo.id,
        nwo: repo.name_with_display_owner,
        filePath: meta.file_path,
        markedForDestroy: false,
        type: "github_file",
      }
    end
  end

  # organizations that own at least one repo in the custom copilot but that the current user is not single-signed-on to
  sig { params(cap_filter: T.untyped, custom_copilot: CustomCopilot).returns(T::Array[String]) }
  def protected_organizations(cap_filter:, custom_copilot:)
    resources = custom_copilot.resources
    repos_in_custom_copilot_ids = resources.select { |resource| resource.resource_type == "github_file" }.map(&:repository_id)
    return [] if repos_in_custom_copilot_ids.empty?
    repos_in_custom_copilot = Repository.where(id: repos_in_custom_copilot_ids)
    orgs_in_custom_copilot = repos_in_custom_copilot.map(&:owner).select { |org| org.is_a?(Organization) }
    unauthorized_orgs = cap_filter.unauthorized_resources(orgs_in_custom_copilot)
    unauthorized_orgs.pluck(:display_login)
  end

  def free_text_resources_react_payload
    free_text_resources.map do |resource|
      meta = T.cast(resource.parsed_metadata, CustomCopilotResource::FreeTextMetadata)
      {
        # The 'id' is used by the DataTable component on the frontend. For persisted records like these we use the database id.
        id: resource.id.to_s,
        databaseId: resource.id,
        text: meta.text,
        name: meta.name,
        markedForDestroy: false,
        type: "free_text",
      }
    end
  end

  def authorized_repositories(resources, viewer:, cap_filter:)
    repos = Repositories::Public.load_repositories(resources.map(&:repository_id))
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
      block: T.nilable(
      T.proc.params(
        resource: CustomCopilotResource
      ).returns(
        T.nilable(MonolithTwirp::Copilotapi::CustomCopilots::V1::Resource)
      ))
    ).returns(MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfig)
  end
  def to_copilot_config_twirp(&block)
    MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfig.new(
      description: description,
      general_instructions: general_instructions,
      icon_url: primary_avatar_path,
      id: id,
      name: name,
      owner_id: owner_id,
      owner_type: twirp_owner_type,
      owner_login: owner.display_login,
      resources: if block
                   # This block lets us keep the authorization logic in the twirp handler
                   resources.map { |resource| block.call(resource) }.compact
                 else
                   resources.map(&:to_copilot_config_twirp)
                 end,
      slug: slug,
    )
  end

  def total_content_size
    # Remove resources that are marked for destruction
    pending_resources = resources.select do |resource|
      !resource.marked_for_destruction?
    end

    # Split resources into github_file resources and other resources
    github_file_type_resources, other_resources = pending_resources.partition do |resource|
      resource.resource_type.to_sym == :github_file
    end

    # Will return a hash where the key is the repository id and the value is the Repository
    visible_repos_indexed_by_id = authorized_repositories(github_file_type_resources, viewer: current_user, cap_filter:).index_by(&:id)

    readable_github_file_type_resources = github_file_type_resources.select do |resource|
      visible_repos_indexed_by_id.key?(resource.repository_id)
    end

    # Add size of general instructions
    total_size = general_instructions.to_s.bytesize

    # Add size of github_file resources
    total_size += readable_github_file_type_resources.sum do |resource|
      resource.size.to_i # Ensure nil size returns 0
    end

    # Add size of other resources
    total_size += other_resources.sum do |resource|
      resource.size
    end
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def validate_total_content_size
    if total_content_size > MAX_CONTENT_SIZE
      errors.add(:base, "The size of the space exceeds the current limit. Please remove a resource and try again.")
    end
  end

  def free_text_resources
    resources.where(resource_type: :free_text)
  end

  def github_file_resources
    resources.where(resource_type: :github_file)
  end
end
