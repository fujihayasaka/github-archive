# typed: true
# frozen_string_literal: true

class RepositoryAction < ApplicationRecord::Domain::Repositories
  include GitHub::Relay::GlobalIdentification
  include Instrumentation::Model
  include GitHub::Validations
  include PrimaryAvatar::Model
  include Avatar::List::Model

  attribute :name, StringFromBinary.new
  attribute :description, StringFromBinary.new

  self.table_name = "repository_actions"
  belongs_to :repository

  has_many :marketplace_categories_repository_actions, dependent: :destroy
  has_many :categories,
    class_name: "Marketplace::Category",
    through: :marketplace_categories_repository_actions,
    source: :marketplace_category,
    disable_joins: true

  has_many :regular_categories,
    -> { where(acts_as_filter: false) },
    class_name: "Marketplace::Category",
    through: :marketplace_categories_repository_actions,
    source: :marketplace_category,
    disable_joins: true

  has_many :filter_categories,
    -> { where(acts_as_filter: true) },
    class_name: "Marketplace::Category",
    through: :marketplace_categories_repository_actions,
    source: :marketplace_category,
    disable_joins: true

  enum :state, { unlisted: 0, listed: 10, delisted: 20 }

  MIN_STARS_FOR_SOCIAL_PROOF = 2
  DESCRIPTION_MAX_LENGTH = 125
  ENDING_PUNCTUATION_REGEX = /[\.,!?]+\z/
  # TODO: remove `azure` when `increase_actions_marketplace_visibility` is active for all users
  GITHUB_MICROSOFT_CREATORS = %w(
    actions
    Azure
    azure
    github
    microsoft
  )

  ACTIONS_ORG_NAME = "actions"

  validates :path, :repository, :name, presence: true
  validates :path, unicode3: true
  validates :path, uniqueness: { scope: [:repository_id], case_sensitive: false }, if: -> { T.unsafe(self).errors[:path].blank? }
  validates :description, length: { maximum: DESCRIPTION_MAX_LENGTH }, if: :listed?
  validates_format_of :color, with: /\A[0-9a-f]{6}\z/iu
  validates_numericality_of :rank_multiplier, greater_than: 0
  validates_with RepositoryActions::SlugValidator, if: :slug_changed?
  validates :slug, presence: true, unicode3: true, if: :listed?
  validate :validate_name_and_slug
  validate :has_signed_marketplace_agreement, if: :action_package_listed?

  validate :validate_published_release, if: :listed?
  validates :security_email, presence: true, if: [:listed?, :owned_by_org?]

  delegate :owner, to: :repository

  has_many :repository_action_releases
  has_many :releases, through: :repository_action_releases

  has_many :published_action_releases,
    -> { where(published_on_marketplace: true) },
    class_name: "RepositoryActionRelease"
  has_many :published_releases,
    -> { where(state: 0) },
    through: :published_action_releases,
    source: :release

  before_validation :set_color
  before_validation :set_icon_name
  before_validation :remove_description_punctuation
  before_validation :set_slug, if: [:name_changed?, :listed?]

  after_commit :synchronize_search_index
  after_destroy_commit :instrument_deletion

  delegate :owner, to: :repository

  scope :featured, -> { where(featured: true) }

  # Actions inside of .github folders are generally not useful outside of their Repository.
  # This filters them out.
  scope :discoverable, -> { where("`#{self.table_name}`.path NOT LIKE (?)", ".github/%") }

  # Returns RepositoryActions that the given User owns or can manage because they're owned by an
  # Organization for which the given User is an admin.
  scope :adminable_by, -> (user) {
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    where(repository_id: user.associated_repository_ids(min_action: :admin))
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
  }

  # Returns RepositoryActions that have not been listed in the Marketplace
  scope :not_in_marketplace, -> { where.not(state: :listed) }
  scope :in_marketplace, -> { where(state: :listed) }

  scope :with_name, -> (name) { where("CONVERT(repository_actions.name USING utf8mb4) LIKE ?", "%#{name}%") }
  scope :owned_by, -> (login) { joins(:repository).and(Repository.where(owner_login: login)) }
  scope :with_state, -> (state) { where(state: state) }

  scope :with_category, -> (slug) do
    category_ids = Marketplace::Category.for_slug(slug).ids
    joins("INNER JOIN marketplace_categories_repository_actions on marketplace_categories_repository_actions.repository_action_id = repository_actions.id")
      .where("marketplace_categories_repository_actions.marketplace_category_id": category_ids)
      .distinct
  end

  def verified_owner?
    async_verified_owner?.sync
  end

  def async_verified_owner?
    async_repository.then do |repository|
      repository.async_owner.then do |owner|
        owner.verified_for_repo_actions?
      end
    end
  end

  def delist_if_unreleased
    return unless listed? && repository_action_releases.published.empty?
    delisted!
  end

  def listed!
    set_slug
    super

    instrument :listed
  end

  def update_from_config!
    update!(config_from_metadata_file)
  end

  def delisted!
    super

    repository_action_releases.update_all(published_on_marketplace: false)
    instrument :delisted
  end

  def instrument_deletion
    actor = User.find_by(id: GitHub.context[:actor_id]) || User.ghost

    instrument :destroy,
      actor_id:  actor.id,
      actor: actor.display_login
  end

  # The color as specified in their metadata file will still be what's persisted
  # in the database. This is purely overriding the color as it is read.
  def color
    if partner_action?
      # blue for actions, white for everyone else
      repository && T.unsafe(repository).owner_display_login.downcase == "actions" ? "0366d6" : "ffffff"
    else
      super
    end
  end

  def icon_color
    RepositoryActions::Colors::ICON_COLOR_MAPPING[color]
  end

  def sign_developer_agreement(actor:, agreement:, org: nil)
    return [agreement, false] unless agreement

    unless adminable_by?(actor)
      agreement.errors.add(:base, "Must have write access to sign for this Action")
      return [agreement, false]
    end

    if org.present? && !org.adminable_by?(actor)
      agreement.errors.add(:base, "Must have org admin access to sign for this Action")
      return [agreement, false]
    end

    if org.present?
      [agreement.sign(user: actor, organization: org), agreement]
    else
      [agreement.sign(user: actor), agreement]
    end
  end

  # Public: Returns true if the given legal agreement has been signed by the integrator. Will
  # check for a signature on the latest version of the integrator agreement if no particular
  # version is given. Defaults to false if no appropriate legal agreement exists.
  #
  # agreement - optional; a specific Marketplace::Agreement for integrators; will default to the
  #             latest version if none is specified
  #
  # Returns a Boolean.
  def has_signed_integrator_agreement?(user:, agreement: nil)
    agreement ||= Marketplace::Agreement.latest_for_integrators

    agreement && agreement.integrator? && agreement.signed_by?(user)
  end

  def org_has_signed_integrator_agreement?(org:, agreement: nil)
    return false if org.nil?

    agreement ||= Marketplace::Agreement.latest_for_integrators

    agreement && agreement.integrator? && agreement.signed_for?(org)
  end

  def base_path
    path == File.basename(path) ? "" : File.dirname(path)
  end

  def metadata_file
    oid = T.unsafe(repository).ref_to_sha(T.unsafe(repository).default_branch)
    T.unsafe(repository).tree_entry(oid, path)
  rescue GitRPC::Error
    # GitRPC::InvalidFullOid will happen if default_branch doesn't exist.
    # GitRPC::NoSuchPath will happen if Dockerfile doesn't exist.
    nil
  end

  def config_from_metadata_file
    return {} unless metadata_file_entry = metadata_file
    T.unsafe(repository).get_action_config_from_metadata_file(metadata_file_entry).slice(:name, :path, :description, :icon_name, :color)
  end

  def external_uses_path_prefix
    resolved_base_path = base_path
    # base path is an empty string, action is at root of the repo.
    return "#{T.unsafe(repository).nwo}@" if resolved_base_path.empty?
    # base_path is a non-empty string, in a folder in the repo.
    "#{T.unsafe(repository).nwo}/#{resolved_base_path}@"
  end

  def local_uses_path_prefix
    resolved_base_path = base_path
    # resolved_base_path = "" if resolved_base_path.length == 1
    return resolved_base_path[1..-1] if resolved_base_path.empty?
    resolved_base_path
  end

  def owned_by_org?
    T.unsafe(repository).owner.organization?
  end

  def permalink(include_host: true)
    if include_host
      "#{GitHub.url}/marketplace/actions/#{slug}"
    else
      "/marketplace/actions/#{slug}"
    end
  end

  def self.ghost_action(default_title)
    {
      name: default_title,
      color: "ffffff",
      icon_color: "23292e",
      # This is used to identify this magic hash in Platform::Objects::RepositoryAction
      ghost_action: true,
    }
  end

  def self.docker_action
    {
      name: "Docker",
      color: "0366d6",
      icon_name: "package",
      icon_color: "ffffff",
      # This is used to identify this magic hash in Platform::Objects::RepositoryAction
      docker_action: true,
    }
  end

  def self.normalize_path(base_path:)
    return "Dockerfile" if base_path.to_s.empty?
    "#{base_path}/Dockerfile"
  end

  def self.from_external_id(external_id: , repository_id: nil, ghost_allowed: false, default_title: nil)
    found_action = with_external_id(external_id: external_id, repository_id: repository_id)
    found_action ||= ghost_action(default_title) if ghost_allowed
    found_action
  end

  def self.with_external_id(external_id: , repository_id: nil)
    return docker_action if external_id.starts_with?("docker://")
    if external_id.starts_with?("./")
      return unless repository_id

      clean_external_id = external_id.chomp("/")
      clean_external_id.gsub!("./", "")

      file_path = "#{clean_external_id}/Dockerfile"
      # If the external_id starts with "./",
      # it is a local reference to an action within the same repository.
      return RepositoryAction.where(path: file_path, repository_id: repository_id).first
    end

    # anything that is not a local action reference, we need
    # an external_id of the format
    # uses = "<user>/<repo>@<commit-ish>" /* path defaults to "/" */
    # uses = "<user>/<repo>/<path>@<commit-ish>"
    parsed_path = external_id.split("@")
    return unless parsed_path.length == 2

    # If the path_segment doesn't contain a `/`, this is not a valid
    # external_id for a RepositoryAction.
    path_segments = parsed_path[0].split("/")
    return if path_segments.length < 2

    # first two segments will be the repo nwo.
    # Find the repository referenced by this NWO.
    repo = Repository.with_name_with_owner(path_segments[0], path_segments[1])

    # If no repo is available with this name, its an invalid external_id
    return unless repo
    # If there's no additional path segments, this is a reference to
    # an action at the root of the repo.
    return RepositoryAction.where(path: "Dockerfile", repository_id: repo.id).first if path_segments.length == 2

    # Calculate the expected path of the Dockerfile.
    file_path = path_segments[2..-1].join("/") + "/Dockerfile"
    RepositoryAction.where(path: file_path, repository_id: repo.id).first
  end

  # Public: Returns true if the action category is github-partner
  def partnership_managed?
    return false if categories.nil?
    categories.where(slug: "github-partners").any?
  end

  def action_runs
    CheckRun::for_app_id(GitHub.launch_github_app&.id, repository_id)
    .where("check_runs.external_id like (?) OR (check_runs.external_id LIKE (?)) OR (check_runs.external_id = (?) AND check_suites_for_app.repository_id=(?))",
     "#{external_uses_path_prefix}%", "docker://%", "./#{local_uses_path_prefix}", repository_id)
  end

  # Public: Synchronize this action with its representation in the search
  # index. All existing actions that are not delisted get indexed.
  def synchronize_search_index
    if can_remove_from_search_index?
      RemoveFromSearchIndexJob.perform_later("repository_action", self.id)
    else
      Search.add_to_search_index("repository_action", self.id)
    end

    self
  end

  def readme(committish: nil)
    async_readme(committish: committish).sync
  end

  def async_readme(committish:)
    async_repository.then do |repository|
      repository.async_default_branch.then do |_branch|
        committish_or_default = committish.presence || repository.default_branch

        PreferredFile.find(
          directory: repository.directory(committish_or_default, base_path),
          subdirectories: %w(.),
          type: :readme,
        )
      end
    end
  end

  def adminable_by?(user)
    # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
    user.associated_repository_ids(min_action: :write).include?(repository_id)
    # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
  end

  # Public: Returns true if the given User has permission to upload a logo or a
  # screenshot associated with this listing. This is used by Avatar#can_upload?
  def avatar_editable_by?(actor)
    adminable_by?(actor)
  end

  def primary_avatar_path
    "/ra/#{id}"
  end

  def target_for_conditional_access
    repository&.owner
  end

  def color_name
    RepositoryActions::Colors.select_by_name_or_hex(color)[:name]
  end

  def set_slug
    self.slug = name.encode("utf-8", undef: :replace, replace: "").parameterize
  end

  def event_payload
    payload = {
      repository_action: self,
      repo: repository
    }
    payload[owner.event_prefix.to_sym] = owner if owner

    payload
  end

  def event_context(prefix: event_prefix)
    {
      prefix.to_sym => slug,
      "#{prefix}_id".to_sym => id,
    }
  end

  def default_branch_workflow_snippet
    lines = []
    lines.push("- name: #{name}")
    lines.push("  uses: #{external_uses_path_prefix}#{T.unsafe(repository).default_branch}")
    lines.push("")
    lines.join("\n")
  end

  def published_releases_workflow_snippet
    published_releases.limit(5).order("id DESC").map do |release|
      tag_name = release.tag_name
      sha = T.unsafe(repository).tags.find(tag_name).commit.oid
      blob = T.unsafe(repository).blob(sha, path)

      yaml = begin
        blob.nil? ? {} : YAML.safe_load(blob.data)
      rescue Psych::SyntaxError, Psych::DisallowedClass
        {}
      end

      inputs = yaml["inputs"] || {}

      lines = []
      lines.push("- name: #{name}")

      if GITHUB_MICROSOFT_CREATORS.include? owner.login
        lines.push("  uses: #{external_uses_path_prefix}#{tag_name}")
      else
        lines.push("  # You may pin to the exact commit or the version.")
        lines.push("  # uses: #{external_uses_path_prefix}#{sha}")
        lines.push("  uses: #{external_uses_path_prefix}#{tag_name}")
      end

      if inputs.any?
        lines.push("  with:")
        inputs.each do |(name, attrs)|
          optional = attrs["required"] ? nil : "optional"
          default = attrs["default"] ? "default is #{attrs["default"]}" : nil
          comment_parts = [optional, default].compact
          comment = comment_parts.any? ? "# #{comment_parts.join(", ")}" : ""

          lines.push("    # #{attrs["description"]}")
          lines.push("    #{name}: #{comment}")
        end
      end

      { release: release, example: lines.join("\n") }
    end
  end

  def latest_tag_or_default_branch
    published_releases.latest.first&.tag_name || T.unsafe(repository).default_branch
  end

  def repository_disabled?
    T.unsafe(repository).disabled_at.present?
  end

  def can_remove_from_search_index?
    destroyed? || delisted? || T.unsafe(repository).private? || repository_disabled?
  end

  def can_viewer_see?(current_user)
    T.unsafe(repository).visible_and_readable_by?(current_user)
  end

  # action_package_listed column denotes whether an action is release based action or action package
  # default value is 0, which means it is a release based action
  # value 1 means it is an action package
  def list_action_package_on_marketplace
    self.action_package_listed = T.unsafe(1)
    listed!
  end

  private

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def partner_action?
    @_partner_action ||= repository && T.unsafe(repository).owner_display_login.downcase.in?(RepositoryActions::ActionPartners::CUSTOM_ICON_PARTNERS)
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def set_color
    primer_color = RepositoryActions::Colors.select_by_name_or_hex(color)

    if primer_color.present?
      self.color = primer_color[:color_hex]
    else
      self.color = RepositoryActions::Colors.generate_default_color(name || "")[:color_hex]
    end
  end

  def remove_description_punctuation
    return if [nil, true, false].include?(self.description)

    self.description = self.description.gsub(ENDING_PUNCTUATION_REGEX, "")
  end

  # If icon name is invalid, we leave it blank and the UI uses the first letter of the Action Name as the icon
  def set_icon_name
    return unless icon_name

    icon_name&.downcase!

    self.icon_name = nil unless RepositoryActions::Icons::NAMES.include? icon_name
  end

  def validate_published_release
    # As part of actions package listing to marketplace, new release records for an action will not be inserted into
    # repository_action_releases as action listing will be done from package settings.
    # To avoid the validation error during the release creation, we are returning early if the action package is already listed on marketplace by checking action_package_listed flag.
    return if repository_action_releases.where(published_on_marketplace: true).exists? || self.action_package_listed

    errors.add(:state, "Action needs a release to be listed")
  end

  def validate_name_and_slug
    return if slug.blank?

    # For transitioning from Dockerfile -> Action.yml. Same name is fine.
    return unless existing_action = RepositoryAction.in_marketplace.find_by(slug: slug)
    return if existing_action.id == id
    return if replacing_existing_action?(existing_action)

    errors.add(:slug, "has already been taken")
  end

  def replacing_existing_action?(existing_action)
    return false unless ["action.yml", "action.yaml"].include?(path)

    existing_action.repository_id == repository_id
  end

  def has_signed_marketplace_agreement
    if GitHub.flipper[:action_package_marketplace].enabled?(User.find_by(id: GitHub.context[:current_user]))
      if T.unsafe(repository).owner.organization?
        validate_org_signed_marketplace_agreement
      else
        validate_user_signed_marketplace_agreement
      end
    end
  end

  def validate_org_signed_marketplace_agreement
    return if org_has_signed_integrator_agreement?(org: T.unsafe(repository).owner)

    errors.add :base, "organization must sign latest developer agreement before publishing an Action"
  end

  def validate_user_signed_marketplace_agreement
    return if has_signed_integrator_agreement?(user: User.find_by(id: GitHub.context[:current_user]))

    errors.add :base, "must sign latest developer agreement before publishing an Action"
  end
end
