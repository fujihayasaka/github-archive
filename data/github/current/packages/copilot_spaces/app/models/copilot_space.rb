# typed: true
# frozen_string_literal: true

class CopilotSpace < ApplicationRecord::Copilot
  include CopilotSpaces::AuthorizationHelper
  include GitHub::Memoizer

  include ::Instrumentation::Model
  include CopilotSpace::PermissionsDependency
  include CopilotSpace::StarsDependency

  include Permissions::Attributes::Wrapper
  include CopilotSpace::SequenceDependency

  after_commit :instrument_created, on: :create
  after_commit :instrument_updated, on: :update
  after_commit :instrument_destroyed, on: :destroy
  before_save :populate_resource_denormalized_columns

  self.permissions_wrapper_class = Permissions::Attributes::CopilotSpace
  self.table_name = "custom_copilots"

  # visibility is deprecated, but need to keep it until FF is fully rolled out
  enum :visibility, { private: 0, org_public: 1 }, validate: true, suffix: true, default: :private
  enum :base_role, { none: 0, custom_copilot_reader: 1, custom_copilot_writer: 2, custom_copilot_admin: 3 }, validate: true, suffix: true, default: :none

  scope :with_chat_attachment, ->(chat_attachment) {
    joins(:resources).where(resources: { copilot_chat_attachment_id: chat_attachment.id })
  }

  # Scopes for filtering copilot spaces
  scope :starred_by, ->(user) {
    # We avoid using joins(:stars).where(stars: { user_id: user.id })
    # because when combining this scope with others using #or,
    # ActiveRecord would require joining the stars table in all queries in the OR chain.
    # Instead, we fetch the starred space IDs first and use where(id: ...),
    # which works seamlessly with OR queries.
    starred_space_ids = user.starred_copilot_spaces.pluck(:custom_copilot_id)
    where(id: starred_space_ids)
  }

  scope :starred_by_with_cap_filter, ->(user, cap_filter) {
    # starred by user, but only those without restricted orgs per cap filter
    starred_space_ids = user.starred_copilot_spaces.pluck(:custom_copilot_id)
    spaces_scope = CopilotSpace.where(id: starred_space_ids)

    # Exclude spaces whose owner org is unauthorized
    # (e.g., user previously starred an org space but hasn't SSOed to that org anymore).
    # Other callers of filter_by_cap_and_sort don't need this because they already
    # pre-filter to authorized orgs (org_owned_spaces) or user-owned spaces.
    owner_ids = spaces_scope.distinct.pluck(:owner_id)
    owner_orgs = Organization.where(id: owner_ids).to_a
    unauthorized_owner_org_ids = cap_filter.unauthorized_resource_ids(owner_orgs)

    if unauthorized_owner_org_ids.any?
      spaces_scope = spaces_scope.where.not(owner_id: unauthorized_owner_org_ids)
    end

    filter_by_cap_and_sort(spaces_scope, cap_filter, user)
  }

  scope :public_spaces, -> { where(base_role: :custom_copilot_reader) }

  # User shared spaces that are visible to current user
  scope :visible_user_spaces, -> (current_user, owner_user) {
    if owner_user.nil? || owner_user.organization?
      return where(id: -1) # return nothing if owner is nil or not a user
    end

    # Find all spaces owned by the user that the current user has been assigned a role in
    spaces_assigned_role_ids = UserRole.where(target_type: "CustomCopilot", actor_type: "User", actor_id: current_user.id)
      .limit(10_000) # Arbitrary limit to prevent spamming the user with too many spaces
      .pluck(:target_id)

    where(owner: owner_user, id: spaces_assigned_role_ids)
  }

  scope :owned_by_user, -> (user, cap_filter) {
    spaces_scope = CopilotSpace.where(owner: user)

    filter_by_cap_and_sort(spaces_scope, cap_filter, user)
  }

  scope :org_owned_spaces, -> (user, cap_filter) {
    orgs = CopilotSpaces::AuthorizationHelper.authorized_orgs(user, cap_filter)
    orgs_ids = orgs.map(&:id)

    # Using promises to parallelize adminable_by? checks
    adminable_promises = orgs.map { |org| org.async_adminable_by?(user) }
    adminable_results = Promise.all(adminable_promises).sync
    adminable_org_ids = orgs.zip(adminable_results)
      .select { |_, adminable| adminable }
      .map { |org, _| org.id }

    # Spaces where the user is an admin of the owning org and the space is private
    org_adminable_private_copilots = CopilotSpace.where(owner: adminable_org_ids, visibility: :private)

    # Org public spaces
    org_public_copilots = CopilotSpace.where(owner: orgs_ids, visibility: :org_public).or(
      CopilotSpace.where(owner: orgs_ids).where.not(base_role: :none)
    )

    spaces_assigned_role_ids = UserRole.where(target_type: "CustomCopilot", actor_type: "User", actor_id: user.id).pluck(:target_id)

    # Spaces from teams that the user belongs to
    teams = orgs_ids.any? ? user.teams.where(organization_id: orgs_ids).to_a : []
    team_ids = teams.any? ? teams.flat_map { |team| [team.id] + team.ancestor_ids }.uniq : []

    if team_ids.any?
      team_assigned_space_ids = UserRole.where(target_type: "CustomCopilot", actor_type: "Team", actor_id: team_ids).pluck(:target_id)
      spaces_assigned_role_ids |= team_assigned_space_ids
    end

    # Org-owned spaces where the user has been assigned a role
    spaces_assigned_role = CopilotSpace.where(id: spaces_assigned_role_ids, owner: orgs)

    spaces_scope = org_adminable_private_copilots.or(org_public_copilots).or(spaces_assigned_role)

    filter_by_cap_and_sort(spaces_scope, cap_filter, user)
  }

  scope :shared_with_user_spaces, -> (user, cap_filter) {
    # Spaces where the user has been assigned a role, excluding those that are org owned or created by the user themselves
    spaces_assigned_role_ids = UserRole.where(target_type: "CustomCopilot", actor_type: "User", actor_id: user.id).pluck(:target_id)

    # This assumes that Spaces are only owned by users or organizations
    spaces_owner_ids = CopilotSpace.where(id: spaces_assigned_role_ids).distinct.pluck(:owner_id)

    owner_id_query = User.where(type: "User", id: spaces_owner_ids).where.not(id: user.id).pluck(:id)

    spaces_scope = CopilotSpace.where(owner_id: owner_id_query, id: spaces_assigned_role_ids)

    filter_by_cap_and_sort(spaces_scope, cap_filter, user)
  }


  # Org parameter is optional, and is used to filter spaces to a specific org
  scope :visible_query, -> (user, cap_filter, org) {
    orgs = CopilotSpaces::AuthorizationHelper.authorized_orgs(user, cap_filter)
    # If an org is provided, filter by it and ensure the user is currently allowed to access it by cap filter
    if org
      return where(id: -1) unless orgs.include?(org)
      orgs = [org]
    end
    orgs_ids = orgs.map(&:id)

    # Using promises to parallelize adminable_by? checks
    adminable_promises = orgs.map { |org| org.async_adminable_by?(user) }
    adminable_results = Promise.all(adminable_promises).sync
    adminable_org_ids = orgs.zip(adminable_results)
      .select { |_, adminable| adminable }
      .map { |org, _| org.id }

    org_adminable_private_copilots = CopilotSpace.where(owner: adminable_org_ids, visibility: :private)

    org_public_copilots = CopilotSpace.where(owner: orgs_ids, visibility: :org_public).or(
      CopilotSpace.where(owner: orgs_ids).where.not(base_role: :none)
    )
    spaces_assigned_role_ids = UserRole.where(target_type: "CustomCopilot", actor_type: "User", actor_id: user.id).pluck(:target_id)

    # Spaces from teams that the user belongs to
    team_ids = orgs_ids.any? ? user.teams.where(organization_id: orgs_ids).flat_map(&:id_and_ancestor_ids).uniq : []

    if team_ids.any?
      team_assigned_space_ids = UserRole.where(target_type: "CustomCopilot", actor_type: "Team", actor_id: team_ids).pluck(:target_id)
      spaces_assigned_role_ids |= team_assigned_space_ids
    end

    org_owned_spaces_assigned_role = CopilotSpace.where(id: spaces_assigned_role_ids, owner: orgs)

    # --- Shared with user spaces and owned by user spaces ---
    # Spaces where the user has been assigned a role
    # Query User table with type: "User" to exclude Organizations (which have type: "Organization")
    spaces_owner_ids = CopilotSpace.where(id: spaces_assigned_role_ids).distinct.pluck(:owner_id)
    # We have to query for User seperately because the owner_type of a CopilotSpace is ALWAYS "user"
    user_owner_ids = User.where(type: "User", id: spaces_owner_ids).pluck(:id)
    # user_owned_spaces are spaces that are owned by the current user and spaces that are shared with the current user
    user_owned_spaces = CopilotSpace.where(owner_id: user_owner_ids, id: spaces_assigned_role_ids)

    # Disable public spaces for EMU users
    if !user.is_enterprise_managed?
      starred_public_spaces = CopilotSpace.starred_by(user).public_spaces

      spaces_scope = org_public_copilots
        .or(org_owned_spaces_assigned_role)
        .or(org_adminable_private_copilots)
        .or(starred_public_spaces)
        .or(user_owned_spaces)
    else
      spaces_scope = org_public_copilots
        .or(org_owned_spaces_assigned_role)
        .or(org_adminable_private_copilots)
        .or(user_owned_spaces)
    end

    spaces_scope
  }

  scope :visible_to, -> (user, cap_filter) {
    visible_spaces = visible_query(user, cap_filter, nil)
    filter_by_cap_and_sort(visible_spaces, cap_filter, user)
  }

  # 350 matches repositories. Keeps this distinct from system instructions and limits use to descriptions.
  MAX_DESCRIPTION_LENGTH = 350
  MAX_GENERAL_INSTRUCTIONS_LENGTH = 4000
  MAX_RESOURCE_COUNT = 300
  BYTES_PER_TOKEN = 3
  DUPLICATE_REPO_ERROR_MESSAGE = "Repository must be unique within a copilot space"

  # The token limit is 96k tokens, 3/4ths of the total 128k token context window.
  # For now, we're using an estimate of 3 bytes per token until we get actual token counting.
  # Does not include general instructions, it is too small to affect our validations.
  # Important! if you update this, make sure to update in ui/packages/copilot-immersive-v1/components/Spaces/TextFileDialog.tsx
  sig { params(viewer: T.nilable(User)).returns(Integer) }
  def self.max_content_size(viewer)
    96_000 * BYTES_PER_TOKEN # 75% of 128k tokens
  end

  # The default icon type and color for custom copilots

  DEFAULT_ICON_TYPE = "DependabotIcon"
  DEFAULT_ICON_COLOR = "blue"

  sig { returns(T.nilable(User)) }
  attr_accessor :current_user

  sig { returns(T.nilable(ConditionalAccess::Filter)) }
  attr_accessor :cap_filter

  sig { returns(ActiveModel::Errors) }
  def cap_validator_errors
    @cap_validator_errors ||= ActiveModel::Errors.new(self)
  end

  sig { params(cap_validator_errors: ActiveModel::Errors).void }
  attr_writer :cap_validator_errors

  after_validation :clear_cap_validator_errors

  belongs_to :owner, polymorphic: true, strict_loading: false

  belongs_to :creator, class_name: "User", optional: true

  has_many :resources, foreign_key: "custom_copilot_id", class_name: "CopilotSpaceResource", inverse_of: :copilot_space
  has_many :user_roles, -> { where("target_type" => "CustomCopilot") },
    as: :target, class_name: "UserRole"

  destroy_dependents_in_background :resources
  destroy_dependents_in_background :user_roles

  accepts_nested_attributes_for :resources, allow_destroy: true, reject_if: :all_blank

  validates :owner, presence: true
  validate :validate_visibility, if: lambda { |c| c.owner.present? }
  validate :validate_unique_repository_resources
  validate :validate_ascii_name
  validates :name, length: { maximum: 255 }, presence: true, uniqueness: { scope: :owner, case_sensitive: false }
  validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }
  validates :icon_url, length: { maximum: 1000 }, allow_nil: true
  validates :general_instructions, length: { maximum: MAX_GENERAL_INSTRUCTIONS_LENGTH }, allow_nil: true
  validates :slug, length: { maximum: 255 }, presence: true, uniqueness: { scope: :owner, case_sensitive: false }
  validates :creator, presence: true, on: :create

  validates :number, presence: true, numericality: { only_integer: true, greater_than: 0 }, on: :create
  validates :number, uniqueness: { scope: [:owner_type, :owner_id] }, on: :create

  validate :validate_resource_count, if: lambda { |c| c.current_user.present? }

  validate :check_cap_validator_errors

  before_validation :generate_slug, if: :name_changed?
  before_validation :generate_icon, on: :create
  before_validation :set_number, on: :create

  sig do
    params(
      spaces_scope: ActiveRecord::Relation,
      cap_filter: ConditionalAccess::Filter,
      user: User,
    ).returns(ActiveRecord::Relation)
  end
  def self.filter_by_cap_and_sort(spaces_scope, cap_filter, user)
    # Remove any eager loading to avoid EagerLoadPolymorphicError when plucking IDs
    spaces_scope_ids = spaces_scope.unscope(:includes).pluck(:id)

    # Get organization IDs from resources
    resource_org_ids = CopilotSpaceResource
      .where(custom_copilot_id: spaces_scope_ids)
      .where.not(organization_id: nil)
      .distinct
      .pluck(:organization_id)

    # Find out which Organizations are unauthorized
    orgs = Organization.where(id: resource_org_ids)
    unauthorized_org_ids = cap_filter.unauthorized_resource_ids(orgs)

    # Find spaces with resources in unauthorized orgs
    spaces_with_protected_orgs = CopilotSpaceResource
      .where(custom_copilot_id: spaces_scope_ids)
      .where(organization_id: unauthorized_org_ids)
      .distinct
      .pluck(:custom_copilot_id)

    # Return spaces excluding those with protected orgs, sorted by name
    CopilotSpace
      .where(id: spaces_scope_ids - spaces_with_protected_orgs)
      .includes(:resources, :stars)
      .preload({ owner: :profile }, :user_roles, :creator)
      .order(:name)
  end

  sig { params(login: String, number: T.any(Integer, String)).returns(CopilotSpace) }
  def self.for_owner_login_and_number!(login, number)
    owner = User.find_by_login(login)
    raise ActiveRecord::RecordNotFound unless owner
    CopilotSpace.find_by!(owner: owner, number: number)
  end

  sig { params(login: String, number: T.any(Integer, String)).returns(CopilotSpace) }
  def self.for_owner_login_and_number_with_user_roles!(login, number)
    owner = User.find_by_login(login)
    raise ActiveRecord::RecordNotFound unless owner
    CopilotSpace.includes(:user_roles).find_by!(owner: owner, number: number)
  end

  sig { params(viewer: User, cap_filter: ConditionalAccess::Filter).returns(T::Array[T.untyped]) }
  def resources_react_payload(viewer:, cap_filter:)
    github_resources = github_resources_react_payload(viewer:, cap_filter:)

    [].concat(
      github_resources,
      free_text_resources_react_payload,
      uploaded_text_file_resources_react_payload(viewer:),
      media_content_resources_react_payload(viewer:),
    )
  end

  sig { params(viewer: User, cap_filter: ConditionalAccess::Filter).returns(T::Array[T.untyped]) }
  def github_resources_react_payload(viewer:, cap_filter:)
    # Will return a hash where the key is the repository id and the value is the Repository
    visible_repos_indexed_by_id = authorized_repositories(github_restricted_resources(viewer:).map { |r| r.repository_id }, viewer:, cap_filter:).index_by(&:id)

    # Remove resources that are not visible to the user
    readable_resources = github_restricted_resources(viewer:).select do |resource|
      visible_repos_indexed_by_id.key?(resource.repository_id)
    end

    readable_file_resources = readable_resources.select(&:github_file_resource_type?).group_by { |resource| resource.repository_id }

    max_content_size = CopilotSpace.max_content_size(current_user).to_f
    file_output = readable_file_resources.flat_map do |repository_id, resources|
      repo = visible_repos_indexed_by_id.fetch(repository_id)
      CopilotSpace::GitHubFileCollection.new(
        max_content_size: max_content_size,
        repository: repo,
        file_resources: resources,
      ).git_info.map do |file_info|
        resource = file_info.file_resource
        {
          id: resource.id.to_s,
          databaseId: resource.id,
          repositoryId: repository_id,
          nwo: repo.name_with_display_owner,
          filePath: resource.metadata["file_path"],
          sizePercentage: file_info.size_percentage,
          markedForDestroy: false,
          fileExists: file_info.exists,
          type: CopilotSpaceResource::Constants::GITHUB_FILE,
          sha: resource.metadata["sha"] || repo.default_branch,
          ownerId: repo.owner_id,
          ownerType: repo.owner.organization? ? "Organization" : "User",
          ownerLogin: repo.owner_display_login,
          private: repo.private?,
        }
      end
    end

    file_output + readable_resources.reject(&:github_file_resource_type?).map do |resource|
      repo = visible_repos_indexed_by_id.fetch(resource.repository_id)

      case resource.resource_type
      when "github_issue"
        meta = resource.metadata
        issue = Issue.find_by(repository: repo, number: meta["number"]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        # If the issue is not found, we don't want to show it in the list
        next if issue.nil?

        {
          # The 'id' is used by the DataTable component on the frontend. For persisted records like these we use the database id.
          id: resource.id.to_s,
          databaseId: resource.id,
          repositoryId: repo.id,
          nwo: repo.name_with_display_owner,
          number: meta["number"],
          sizePercentage: resource.size_percentage,
          markedForDestroy: false,
          type: resource.resource_type,
          title: issue.title,
          url: issue.url,
          ownerId: repo.owner_id,
          ownerType: repo.owner.organization? ? "Organization" : "User",
          ownerLogin: repo.owner_display_login,
          private: repo.private?,
        }
      when "github_pull_request"
        meta = resource.metadata
        pull_request = Issue.includes(:pull_request).find_by(repository: repo, number: meta["number"]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        # If the issue is not found, we don't want to show it in the list
        next if pull_request.nil?

        {
          # The 'id' is used by the DataTable component on the frontend. For persisted records like these we use the database id.
          id: resource.id.to_s,
          databaseId: resource.id,
          repositoryId: repo.id,
          nwo: repo.name_with_display_owner,
          number: meta["number"],
          sizePercentage: resource.size_percentage,
          markedForDestroy: false,
          type: resource.resource_type,
          title: pull_request.title,
          url: pull_request.url,
          ownerId: repo.owner_id,
          ownerType: repo.owner.organization? ? "Organization" : "User",
          ownerLogin: repo.owner_display_login,
          private: repo.private?,
        }
      when "repository"
        meta = T.cast(resource.parsed_metadata, CopilotSpaceResource::RepositoryMetadata)

        {
          # The 'id' is used by the DataTable component on the frontend. For persisted records like these we use the database id.
          id: resource.id.to_s,
          databaseId: resource.id,
          repositoryId: repo.id,
          nwo: repo.name_with_display_owner,
          markedForDestroy: false,
          type: "repository",
          ownerType: repo.owner.organization? ? "Organization" : "User",
          ownerAvatarUrl: repo.owner.primary_avatar_url,
          ownerId: repo.owner_id,
          ownerLogin: repo.owner_display_login,
          private: repo.private?,
        }
      end
    end.compact
  end

  sig { returns(T::Array[User]) }
  def orgs
    repos_in_copilot_space_ids = resources.select { |resource| resource.resource_type == CopilotSpaceResource::Constants::GITHUB_FILE }.map(&:repository_id)

    if repos_in_copilot_space_ids.empty?
      return owner.is_a?(Organization) ? [owner] : []
    end

    repos_in_copilot_space = Repository.where(id: repos_in_copilot_space_ids).includes(:owner)
    orgs_in_copilot_space = repos_in_copilot_space.map(&:owner).compact.select { |org| org.is_a?(Organization) }
    orgs_in_copilot_space = orgs_in_copilot_space + [owner] if owner.is_a?(Organization)
    orgs_in_copilot_space.uniq
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
        type: CopilotSpaceResource::Constants::FREE_TEXT,
      }
    end
  end

  sig { params(viewer: User).returns(T::Array[T::Hash[String, T.untyped]]) }
  def uploaded_text_file_resources_react_payload(viewer:)
    uploaded_text_file_resources.map do |resource|
      resource = T.cast(resource, CopilotSpaceResource)
      meta = T.cast(resource.parsed_metadata, CopilotSpaceResource::UploadedTextFileMetadata)
      url = "#{resource.copilot_chat_attachment&.permalink}?copilot_space_id=#{id}"

      {
        id: resource.id.to_s,
        databaseId: resource.id,
        name: meta.name,
        copilotChatAttachmentId: resource.copilot_chat_attachment_id,
        sizePercentage: resource.size_percentage,
        markedForDestroy: false,
        type: CopilotSpaceResource::Constants::UPLOADED_TEXT_FILE,
        url:,
      }
    end
  end

  sig { params(viewer: User).returns(T::Array[T::Hash[String, T.untyped]]) }
  def media_content_resources_react_payload(viewer:)
    return [] unless viewer.feature_flag_enabled?(:copilot_custom_copilots_images, default: false)

    media_content_resources.map do |resource|
      meta = T.cast(resource.parsed_metadata, CopilotSpaceResource::MediaContentMetadata)
      {
        id: resource.id.to_s,
        databaseId: resource.id,
        copilotChatAttachmentId: resource.copilot_chat_attachment_id,
        url: meta.url,
        mediaType: meta.media_type,
        name: meta.name,
        height: meta.height,
        width: meta.width,
        sizePercentage: resource.size_percentage,
        markedForDestroy: false,
        type: CopilotSpaceResource::Constants::MEDIA_CONTENT,
      }
    end
  end

  sig { params(repository_ids: T::Array[T.untyped], viewer: T.nilable(User), cap_filter: T.untyped).returns(T::Array[Repository]) }
  def authorized_repositories(repository_ids, viewer:, cap_filter:)
    repos = Repositories::Public.load_repositories(repository_ids).includes(:owner)

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

  # Converts the CopilotSpace to a Twirp CustomCopilotConfig format for API responses.
  #
  # @param viewer [User] The user requesting the copilot configuration
  # @param twirp_repo_access_allowed [Proc, nil] Optional block that takes a Repository
  #   and returns a Boolean indicating whether the viewer has access to that repository.
  #   When provided, this block is used to filter GitHub-restricted resources based on
  #   repository access permissions. If no block is given, no resources
  #   are included in the configuration.
  #
  # @return [MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfig]
  #   The copilot configuration with filtered resources based on access permissions, as well as images, file uploads, and free text
  #
  # @example With repository access checking
  #   copilot.to_copilot_config_twirp(user) { |repo| user.can_access?(repo) }
  #
  # @example Without repository access checking (no resources will be included)
  #   copilot.to_copilot_config_twirp(user)
  sig do
    params(
      viewer: User,
      twirp_repo_access_allowed:
      T.nilable(T.proc.params(
        repo: Repository
      ).returns(
        T::Boolean
      ))
    ).returns(MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfig)
  end
  def to_copilot_config_twirp(viewer, &twirp_repo_access_allowed)
    allowed_resources = []

    if block_given?
      resources_with_repos = github_restricted_resources(viewer:)
      # Will return a hash where the key is the repository and the value is an array of resources
      resources_by_repo = resources_with_repos.group_by(&:repository)
      allowed_resources = resources_by_repo.map do |repo, resources|
        # Check if the repo is readable by the viewer and allowed by the twirp_repo_access_allowed proc
        if twirp_repo_access_allowed.call(repo)
          file_resources, other_resources = resources.partition do |resource|
            resource.resource_type.to_sym == :github_file
          end
          # Batch hydrate file resources
          hydrated_file_resources = CopilotSpaceResource::GitHubFileMetadata.batch_files_to_copilot_config_twirp(repo, file_resources)
          # Hydrate other repo related resources
          hydrated_resources = other_resources.map { |resource| resource.twirp_resource(opts: {}) }
          hydrated_file_resources + hydrated_resources
        else
          []
        end
      end
      # add unrestricted resources
      allowed_resources += unrestricted_resources.map { |resource| resource.twirp_resource }
    end

    MonolithTwirp::Copilotapi::CustomCopilots::V1::CustomCopilotConfig.new(
      description: description,
      general_instructions: general_instructions,
      id: id,
      name: name,
      owner_id: owner_id,
      owner_type: twirp_owner_type,
      owner_login: owner.display_login,
      resources: allowed_resources.flatten.compact,
      slug: slug,
      number: number,
    )
  end

  def size_percentage
    (total_content_size / CopilotSpace.max_content_size(current_user).to_f * 100).round(10)
  end

  memoize def pending_resources
    # Remove resources that are marked for destruction
    resources.select do |resource|
      !resource.marked_for_destruction?
    end
  end

  sig { returns(Integer) }
  def total_content_size
    GitHub.dogstats.distribution_time("copilot-spaces.total_content_size") do
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
      readable_github_file_resources, other_readable_github_resources = readable_github_resources.partition do |resource|
        resource.github_file_resource_type?
      end

      readable_github_file_resources = readable_github_file_resources.group_by { |resource| resource.repository_id }

      max_content_size = CopilotSpace.max_content_size(current_user).to_f
      file_size = readable_github_file_resources.flat_map do |repository_id, resources|
        repo = visible_repos_indexed_by_id.fetch(repository_id)
        CopilotSpace::GitHubFileCollection.new(
          max_content_size: max_content_size,
          repository: repo,
          file_resources: resources,
        ).git_info.map(&:size)
      end

      total_size = file_size.sum + other_readable_github_resources.sum do |resource|
        resource.size.to_i # Ensure nil size returns 0
      end

      # Add size of other resources
      total_size += other_resources.sum do |resource|
        resource.size
      end
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

  sig { returns(T.nilable(Integer)) }
  def set_number
    return if self.number
    return unless owner

    create_sequence_if_missing
    self.number = Sequence.next(self)
  end

  sig { params(viewer: User).returns(T::Boolean) }
  def shared_with?(viewer)
    !!(owner&.user? && viewer != owner)
  end

  sig { returns(T::Boolean) }
  def has_collaborators?
    return false unless owner.present?

    # Use loaded? to check if association is preloaded, then extract IDs efficiently
    actor_ids = if user_roles.loaded?
      user_roles.map(&:actor_id)
    else
      user_roles.pluck(:actor_id)
    end
    excluded_ids = [owner.id, creator_id].compact
    collaborators = actor_ids.uniq - excluded_ids

    collaborators.any?
  end

  # Used only for staff tools pages
  sig { returns(Integer) }
  def collaborators_count
    return 0 unless owner.present?

    actor_ids = if user_roles.loaded?
      user_roles.map(&:actor_id)
    else
      user_roles.pluck(:actor_id)
    end
    excluded_ids = [owner.id, creator_id].compact
    collaborators = actor_ids.uniq - excluded_ids

    collaborators.size
  end

  sig { returns(T::Boolean) }
  def public?
    !!(owner&.user? && base_role == "custom_copilot_reader")
  end

  sig { returns(T::Boolean) }
  def reportable?
    !!(owner != current_user && !none_base_role?)
  end

  sig { params(viewer: User, resource: T.any(T::Hash[T.untyped, T.untyped], ActionController::Parameters)).returns(T::Boolean) }
  def validate_media_content_url(viewer, resource)
    # If the resource type is not media content or is being deleted, skip validation
    return true unless resource[:resource_type].to_s == CopilotSpaceResource::Constants::MEDIA_CONTENT
    return true if resource[:_destroy]

    meta = resource[:metadata]

    return true unless meta.present? && meta[:url].present? && resource[:copilot_chat_attachment_id].present?

    # Check if URL is being modified on existing resources
    if resource[:id].present?
      existing_resource = resources.find_by(id: resource[:id])
      if existing_resource.present?
        existing_url = existing_resource.metadata["url"]
        new_url = meta[:url]

        return false if existing_url != new_url
      end
    end

    # Validate that URL matches the associated chat attachment
    attachment = Copilot::ChatAttachment.find_by(id: resource[:copilot_chat_attachment_id])

    return false if attachment.nil?
    return false unless meta[:url] == attachment.permalink

    true
  end

  # shareable refers to whether SpacesIndividualSharing is enforced for this Space
  def shareable?
    return true unless FeatureFlag.vexi.enabled?(:copilot_spaces_individual_policies_ga, current_user, default: false)

    if owner.user?
      Copilot::Policies::SpacesIndividualSharing.effective_value(Copilot::User.new(owner)) == "enabled"
    else
      true
    end
  end

  def can_individually_access?
    return true unless FeatureFlag.vexi.enabled?(:copilot_spaces_block_individual_access, current_user, default: false)

    if owner.user? && current_user
      Copilot::Policies::SpacesIndividualAccess.effective_value(Copilot::User.new(T.must(current_user))) == "enabled"
    else
      true
    end
  end

  sig { returns(T::Boolean) }
  def enterprise_managed?
    enterprise_managed_business.present?
  end

  sig { returns(T.nilable(Business)) }
  def enterprise_managed_business
    case owner
    when Organization
      owner.business if owner.enterprise_managed_user_enabled?
    when User
      owner.enterprise_managed_business if owner.is_enterprise_managed?
    end
  end

  private

  # Populate denormalized repository_id and organization_id columns on resources
  # Uses batch loading to avoid N+1 queries when saving multiple resources via accepts_nested_attributes_for
  def populate_resource_denormalized_columns
    # Find resources that need repository_id populated from metadata
    resources_needing_update = resources.select do |resource|
      resource[:denormalized_repository_id].nil? && resource.metadata&.dig("repository_id").present?
    end

    return if resources_needing_update.empty?

    # Batch load all repositories with their owners in a single query
    repo_ids = resources_needing_update.map { |r| r.metadata["repository_id"] }.compact.uniq
    repos_by_id = Repository.where(id: repo_ids).includes(:owner).index_by(&:id)

    # Populate each resource from the cached repositories
    resources_needing_update.each do |resource|
      repo_id = resource.metadata["repository_id"]
      resource[:denormalized_repository_id] = repo_id

      repo = repos_by_id[repo_id]
      if repo.present? && repo.owner&.organization?
        resource[:organization_id] = repo.owner_id
      end
    end
  end

  def generate_icon
    self.icon_type = DEFAULT_ICON_TYPE if icon_type.blank?
    self.icon_color = DEFAULT_ICON_COLOR if icon_color.blank?
  end

  def validate_resource_count
    if resources.size > MAX_RESOURCE_COUNT
      errors.add(:base, "You can select a maximum of #{MAX_RESOURCE_COUNT} sources.")
    end
  end

  def validate_unique_repository_resources
    repository_resource_repo_ids = pending_resources
      .select { |r| r.repository_resource_type? }
      .map { |r| r.metadata["repository_id"] }

    # Check if there are any duplicate repository ids
    if repository_resource_repo_ids.uniq.length != repository_resource_repo_ids.length
      errors.add(:base, DUPLICATE_REPO_ERROR_MESSAGE)
    end
  end

  def validate_visibility
    if !owner.organization? && !private_visibility?
      errors.add(:base, "Only organization owned spaces can be shared.")
    end
  end

  def validate_ascii_name
    if name && (!name.ascii_only? || (!name.empty? && name.parameterize.empty?))
      errors.add(:name, "can only contain ASCII letters, digits, spaces, and basic symbols.")
    end
  end

  # Copies errors from the CAP validation (which runs before the save transaction)
  def check_cap_validator_errors
    errors.merge!(cap_validator_errors) if cap_validator_errors.present?
  end

  def clear_cap_validator_errors
    cap_validator_errors.clear
  end

  def free_text_resources
    resources.where(resource_type: :free_text)
  end

  def uploaded_text_file_resources
    resources
      .includes(:copilot_chat_attachment)
      .where(resource_type: :uploaded_text_file)
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

  def media_content_resources
    resources.where(resource_type: :media_content)
  end

  def repository_resources(viewer:)
    resources.where(resource_type: :repository)
  end

  sig { params(viewer: User).returns(T::Array[CopilotSpaceResource]) }
  def github_restricted_resources(viewer:)
    github_file_resources + github_issue_resources + github_pull_request_resources + repository_resources(viewer:)
  end

  sig { returns(T::Array[CopilotSpaceResource]) }
  def unrestricted_resources
    free_text_resources + uploaded_text_file_resources + media_content_resources
  end

  sig { void }
  def instrument_created
    instrument :created
  end

  sig { void }
  def instrument_updated
    instrument :updated
  end

  sig { void }
  def instrument_destroyed
    instrument :deleted
  end

  def event_payload
    {
      id: id,
      number: number,
      name: name,
      description: description,
      general_instructions: general_instructions,
      visibility: visibility,
      base_role: base_role,
      resource_count: resources.size,
      has_collaborators: has_collaborators?,
      public: public?,
      creator: creator,
      actor: current_user,
      org: owner&.organization? ? owner : nil,
      user: owner&.user? ? owner : nil,
    }
  end
end
