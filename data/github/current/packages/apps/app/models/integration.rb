# typed: true
# frozen_string_literal: true

require "oauth_util"

class Integration < ApplicationRecord::Domain::Integrations
  LEGACY_EVENT_ID_CUTTOFF = 68_000

  include PrimaryAvatar::Model
  include Avatar::List::Model
  include GitHub::UserContent
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include OauthAccess::Provider
  include OauthAccess::ClientId
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations
  include AppNameValidity
  include Marketplace::Listable
  include Proxima::Syncable
  include Rest::HasPinnedApiVersion
  include Spam::Spammable
  include AppEmuOwnership
  include Integration::VisibilityDependency

  include ::Permissions::Attributes::Wrapper
  self.permissions_wrapper_class = ::Permissions::Attributes::Integration

  attribute :description, StringFromBinary.new

  # Values defined by PREVIEW_SUBJECTS_AND_FEATURE_FLAGS in User::Resources
  COPILOT_PERMISSION = "copilot_messages"

  # A multiplier applied to abuse/secondary rate limits
  # for github trusted applications.
  TRUSTED_ABUSE_LIMIT_MULTIPLIER = 4

  # default error message for an invalid URL
  INVALID_URL_MESSAGE = "must be a valid URL".freeze

  IDENTICON_TYPE = "app".freeze

  KEY_PREFIX_V1 = "Iv1".freeze

  # Public: The Regexp describing the format of an Integrations's string
  # key value.
  KEY_PATTERN_V1 = %r{
   \A               # start
   #{KEY_PREFIX_V1} # Letter I prefix  the token format version
   \.               # a period
   [a-f0-9]{16}     # the random portion of the token
   \z               # end
  }xi
  CLIENT_ID_LENGTH = 8

  KEY_PREFIX_V2 = "Iv2".freeze

  # Public: The Regexp describing the format of an Integrations's string
  # key value.
  KEY_PATTERN_V2 = %r{
   \A               # start
   #{KEY_PREFIX_V2} # Letter I prefix  the token format version
   [a-z0-9]{3}      # encoded stamp id
   [a-z0-9]{14}     # the random portion of the token
   \z               # end
  }xi
  CLIENT_ID_V2_LENGTH = 14

  def self.client_id_types
    {
      KEY_PATTERN_V1 => :v1,
      KEY_PATTERN_V2 => :v2
    }
  end

  def self.client_id_prefix(type:)
    case type
    when :v1
      KEY_PREFIX_V1
    when :v2
      KEY_PREFIX_V2
    end
  end

  def self.client_id_seperator(type:)
    case type
    when :v1
      "."
    when :v2
      opaque_generated_location_specifier
    end
  end

  def self.client_id_random_part_length(type:)
    type == :v1 ? CLIENT_ID_LENGTH : CLIENT_ID_V2_LENGTH
  end

  before_validation :generate_client_id_if_needed
  validates_presence_of :key
  validates_uniqueness_of :key, case_sensitive: false

  RESERVED_SLUGS = %w(new feature).freeze

  ALLOWED_OWNER_TYPES = %w(User Business).freeze

  MAX_APPLICATION_CALLBACK_URLS = 10

  # Public: The User, Organization, or Business which owns this integration.
  belongs_to :owner, polymorphic: true
  setup_spammable :owner

  # If owner is a Business, ignore its default_scope of `where(deleted_at: nil)`
  def owner
    if enterprise_owned?
      Business.unscoped { super }
    else
      super
    end
  end

  alias user owner

  # Public: A version of the app's owner that is suitable for use in views and
  # API responses. Accounts for things like multi-tenancy, synchronization and
  # first/third-party behavior.
  #
  # Returns a AppDisplayOwner.
  def display_owner
    AppDisplayOwner.new(app: self, actual_owner: owner)
  end

  # Category to which the integration belongs in Marketplace.
  belongs_to :marketplace_category, class_name: "Marketplace::Category"

  # Public: Alias async_user to the async_owner method added by ApplicationRecord::Base based on the
  # belongs_to :owner association above so that the OauthApplication object in the GitHub Platform
  # can handle OauthApplication or Integration instances equally.
  def async_user
    async_owner
  end

  # Public: A bot that the integration can use for making requests on its own
  # behalf.
  belongs_to :bot, inverse_of: :integration, autosave: true

  # Public: Installations for this integration.
  has_many :installations,
    class_name: "IntegrationInstallation"
  destroy_dependents_in_background :installations

  # Public: Hook used to deliver events to an integration. This one Hook
  # receives events for all of the integration's installations.
  has_one :hook,
    class_name: "Hook",
    as: :installation_target,
    inverse_of: :installation_target,
    dependent: :destroy

  accepts_nested_attributes_for :hook,
    reject_if: :all_blank,
    update_only: true,
    allow_destroy: true

  validates_associated :hook

  # Public: The keys used to sign and verify integration access tokens.
  # Supports multiple keys to allow for rotating keys.
  has_many :public_keys,
    class_name: "IntegrationKey",
    dependent: :destroy

  accepts_nested_attributes_for :public_keys,
    reject_if: :all_blank,
    allow_destroy: true,
    update_only: true

  # Public: The listing information for the Integration Directory, if any.
  has_one :integration_listing,
    as: :integration,
    dependent: :destroy

  # Public: Association relationship for IntegrationTransfers.
  has_one :transfer,
    class_name: "IntegrationTransfer",
    dependent: :destroy

  has_many :versions,
    -> { order("number") },
    class_name: "IntegrationVersion",
    autosave: true
  destroy_dependents_in_background :versions

  has_one :latest_version,
    -> { order("number DESC") },
    autosave: true,
    class_name: "IntegrationVersion",
    inverse_of: :integration

  accepts_nested_attributes_for :latest_version,
  reject_if: :all_blank,
  allow_destroy: true

  has_one :alias,
    class_name: "IntegrationAlias",
    autosave: true,
    dependent: :destroy

  has_one :enterprise_installation

  has_many :application_callback_urls,
    as: :application,
    inverse_of: :application,
    dependent: :destroy

  # Public: Client secrets for application.
  has_many :client_secrets,
    -> { order(id: :desc) },
    class_name: "IntegrationClientSecret",
    inverse_of: :integration,
    dependent: :destroy

  accepts_nested_attributes_for :client_secrets,
    reject_if: :all_blank,
    allow_destroy: true

  accepts_nested_attributes_for :application_callback_urls, reject_if: :all_blank, allow_destroy: true

  # DefaultIntegrationPermissions representing the default permissions
  # that this integration requests at installation time.
  delegate :default_permission_records, to: :latest_version

  # HookEventSubscriptions representing the default event types that this
  # integration requests at installation time.
  delegate :default_event_records, to: :latest_version

  # Public: OauthAccesses granted to this Integration.
  has_many :accesses,
    class_name: "OauthAccess",
    as: :application
  destroy_dependents_in_background :accesses

  # Public: OauthAuthorizations granted to this Integration.
  has_many :authorizations,
    class_name: "OauthAuthorization",
    as: :application
  destroy_dependents_in_background :authorizations

  has_many :pending_installation_requests,
    class_name: "IntegrationInstallationRequest"
  destroy_dependents_in_background :pending_installation_requests

  # Public: IpAllowlistEntries for connections from this Integration
  has_many :ip_allowlist_entries, as: :owner, dependent: :destroy
  accepts_nested_attributes_for :ip_allowlist_entries, reject_if: :all_blank, allow_destroy: true

  has_many :integration_install_triggers, dependent: :destroy
  accepts_nested_attributes_for :integration_install_triggers, reject_if: :all_blank, allow_destroy: true

  # Public: The owner of this integration.
  # column :owner_id, :owner_type
  validates_presence_of :owner
  validates :owner_type, presence: true, inclusion: ALLOWED_OWNER_TYPES

  # Public: The bot account for this integration.
  # column :bot_id
  validates_presence_of :bot

  # Public: String URL of this integration.
  # column :url
  validates_presence_of :url
  validate :validate_integration_url

  # Public: String setup URL of this integration which we'll
  # redirect a user to after installation of the integration.
  # column :setup_url
  validate :validate_setup_url

  # Public: String name of this integration.
  # column :name
  validates_presence_of :name
  validate :restrict_names_with_github
  validate :restrict_names_with_urls
  validates :name, unicode3: true

  # Public: String slug of this integration.
  # column :slug
  validate :validate_integration_slug, if: :name_changed?
  validate :slug_is_not_reserved, if: :slug_changed?
  validate :slug_is_not_existing_owner, if: :slug_changed?
  def to_param
    slug
  end

  attr_reader :invalid_permissions
  validate :validate_permission_actions

  validate :validate_state, if: -> (integration) { integration.state_changed? && integration.suspended? }
  validates :suspended_reason, presence: true, if: -> { T.bind(self, Integration).suspended? }

  validates_with CreatedApplicationsLimitValidator, on: :create

  validates_associated :application_callback_urls

  validates_length_of :application_callback_urls,
    maximum: MAX_APPLICATION_CALLBACK_URLS,
    message: "has too many callback urls (maximum is #{MAX_APPLICATION_CALLBACK_URLS})"

  # There must be at least one callback URL if #request_oauth_on_install is set to be true.
  validates_length_of :application_callback_urls,
    minimum: 1,
    message: "at least one callback URL is required",
    if: :request_oauth_on_install?

  validate :validate_visibility

  before_validation :set_default_hook_attributes

  before_validation :normalize_bgcolor
  before_validation :generate_slug,          if: :name_changed?
  before_validation :generate_bot_slug,      if: :slug_changed?
  before_validation :generate_alias_slug,    if: :slug_changed?

  after_validation :format_version_error_messages
  after_validation :prevent_setup_on_update, if: :setup_url_missing?

  before_create :default_user_token_expiration_enabled
  attr_accessor :user_token_expiration_enabled

  after_create_commit :instrument_creation
  after_destroy_commit :instrument_deletion

  before_update :update_latest_version

  after_update_commit :instrument_suspension, if: -> { T.bind(self, Integration).saved_change_to_state? && suspended? }
  after_update_commit :instrument_unsuspension, if: -> { T.bind(self, Integration).saved_change_to_state? && active? }

  has_one :integration_agent, dependent: :destroy

  after_destroy :destroy_bot_async, if: :destroy_bot_asynchronously
  after_destroy :destroy_bot, unless: :destroy_bot_asynchronously

  attr_accessor :destroy_bot_asynchronously

  include Integration::ConfigurationDependency
  include Integration::RepositoriesDependency
  include Integration::Sequence

  setup_sequence

  scope :with_latest_version, -> { includes(:latest_version) }

  # Returns Integrations that the given User owns or can manage because they're owned by an
  # Organization for which the given User is an admin.
  scope :adminable_by, ->(user) {
    user_ids = [user.id]

    adminable_org_ids = Ability.user_admin_on_organizations(
      actor_id: user.id,
    ).pluck(:subject_id)
    user_ids = adminable_org_ids.concat(user_ids) if adminable_org_ids.present?

    where(owner_id: user_ids)
  }

  # Returns Integrations that do not have a Marketplace::Listing.
  scope :not_in_marketplace, -> {
    left_outer_joins(:marketplace_listing).where(marketplace_listings: { listable_id: nil })
  }

  # Excludes private Integrations that are configured as not user-installable.
  scope :user_installable, -> {
    # Gets around:
    # DEPRECATION WARNING: Class level methods will no longer inherit scoping from `user_installable` in Rails 6.1. To continue using the scoped relation, pass it into the block directly.
    scoping do
      not_installable = Apps::Internal::Query.new.without_capability(:user_installable, type: Integration)
      return all if not_installable.empty?
      where.not(id: not_installable)
    end
  }

  # TODO: Get rid of `no_repo_permissions_allowed` as its no longer used
  attr_writer :skip_restrict_names_with_github_validation, :skip_generate_slug, :no_repo_permissions_allowed,
              :skip_slug_owner_check

  scope :not_marked_for_deletion, -> { where(deleted_at: nil) }

  scope :not_for_github_connect, -> {
    where.not(id: EnterpriseInstallation.pluck(:integration_id))
  }

  # Used when integrations have been scoped to a repository by installations.
  #
  # This will likely not work on the full integrations table as there is
  # currently no combined index on name and slug.
  scope :name_or_slug_like, -> (query_str) {
    query = "%#{ActiveRecord::Base.sanitize_sql_like(query_str)}%"
    where(["#{table_name}.name LIKE ? OR #{table_name}.slug LIKE ?", query, query])
  }

  # Public: Determines the number of Integrations created (owned) by user
  #
  # Returns an Integer
  def self.created_by_count(user)
    user.integrations.count
  end

  def self.from_owner_and_slug!(viewer: nil, slug:, user_login: nil, business_slug: nil)
    found = from_owner_and_slug(viewer: viewer, slug: slug, user_login: user_login, business_slug: business_slug)
    raise ActiveRecord::RecordNotFound unless found
    found
  end

  def self.from_owner_and_slug(viewer: nil, slug:, user_login: nil, business_slug: nil)
    finder = user_installable

    if user_login || business_slug
      return nil unless GitHub.flipper[:owner_scoped_github_apps].enabled?(viewer)

      owner = if user_login
        User.find_by(login: user_login)
      else
        Business.find_by(slug: business_slug)
      end
      return nil unless owner

      finder = finder.where(owner: owner)
      finder.find_by(slug: slug)
    else
      # Legacy "unique by slug" apps should have a canonical IntegrationAlias
      # record
      app_alias = IntegrationAlias.find_by(slug: slug)
      return nil unless app_alias.present?
      finder.find_by(id: app_alias.integration_id)
    end
  end

  def self.find_external_app!(slug:)
    integration = Integration.user_installable.find_by!(slug: slug)
    raise ActiveRecord::RecordNotFound unless integration.synchronized_dotcom_app?

    integration
  end

  def to_s
    name
  end

  def url
    if self.feature_enabled?(:templatize_integration_url, memoize: false) && generate_tenant_scoped_url?(raw_url)
      return ::ProximaAppRequest::TenantScopedUrl.generate(T.must(raw_url), self)
    end

    raw_url
  end

  def raw_url
    read_attribute(:url)
  end

  # Public: The value of the `setup_url` attribute. If the app is syncable to Proxima and has
  # a templated URL, we will interpolate the hostname into the URL (e.g., `https://{hosname}/callback` ->
  # `https://staffship01-ghe.com/callback`).
  #
  # Returns: String
  def setup_url
    if generate_tenant_scoped_url?(raw_setup_url)
      return ::ProximaAppRequest::TenantScopedUrl.generate(T.must(raw_setup_url), self)
    end

    raw_setup_url
  end

  # Public: The value of the `setup_url` attribute stored in the DB
  #
  # Returns: String
  def raw_setup_url
    read_attribute(:setup_url)
  end

  def name=(str)
    self[:name] = str&.strip
  end

  # Public: The latest version for the integration
  def latest_version
    super || build_latest_version
  end

  # Public: The collection of resources that this integration requests access to.
  #
  # Example
  #   permissions
  #   # => { "statuses" => :write, "issues" => :read }
  #
  # Returns a Hash
  delegate :default_permissions, to: :latest_version

  # Public: The collection of resources that this integration requests access to.
  #
  # Example
  #   async_default_permissions.sync
  #   # => { "statuses" => :write, "issues" => :read }
  #
  # Returns a Promise
  def async_default_permissions
    async_latest_version.then do |version|
      version.async_default_permissions
    end
  end

  # Public: Set the collection of resources this integration requests access to.
  #
  # assigned_permissions - A Hash of resource Strings to permission Symbols.
  #
  # Returns the Hash of assigned permissions.
  def default_permissions=(assigned_permissions)
    current_version.default_permissions = assigned_permissions
  rescue ArgumentError => e
    raise e unless /not a valid action/.match e.message
    # copy the assigned permissions so that we can build the errors on validation
    @invalid_permissions = assigned_permissions
  end

  # Public: The collection of event names that this integration subscribes to.
  #
  # Example
  #   events
  #   # => ["issues", "pull_request"]
  #
  # Returns an Array
  delegate :default_events, to: :latest_version

  # Public: The collection of event names that this integration subscribes to.
  #
  # Example
  #   async_default_events.sync
  #   # => ["issues", "pull_request"]
  #
  # Returns a Promise
  def async_default_events
    async_latest_version.then do |version|
      version.async_default_events
    end
  end

  # Public: Set the collection of event names this integration should subscribe
  # to.
  #
  # event_names - An Array of event names.
  #
  # Returns an Array of subscribed event names.
  def default_events=(event_names)
    # Exclude any integrator events.
    event_names -= Integration::Events::INTEGRATOR_EVENTS

    # In the event that default events are set
    # on a new record, there won't be a hook even if there
    # are hook attributes.
    #
    # Build a hook so that if there are failures
    # they show up in the UI.
    if event_names.any? && new_record? && hook.nil?
      build_hook # The other default settings are set at before_validation
    end

    return [] if hook.nil?

    transaction do
      current_version.default_events = event_names

      # In order to support any all possible events we will add
      # to the list of events instead of replacing it everytime the
      # default events are updated.
      T.must(hook).add_events(event_names)
    end
  end

  delegate :default_content_references, to: :latest_version

  def default_content_references=(content_references)
    current_version.default_content_references = content_references
  end

  def content_reference=(content_reference)
    return if content_reference.empty?
    self.default_content_references = content_reference.reduce({}) { |h, v| h[v] = "domain"; h }
  end

  def async_target_for_conditional_access
    async_owner
  end

  # Public: The collection of event names that this integration subscribes to,
  # but does not pass along to its integration versions nor its installations.
  #
  # Example
  #   integrator_events
  #   # => ["security_advisory"]
  #
  # Returns an Array
  def integrator_events
    return [] if hook.nil?
    T.must(hook).events & Integration::Events::INTEGRATOR_EVENTS
  end

  # Public: Set the collection of integrator event names this integration should
  # subscribe to. Unlike #default_events=, these events are not persisted to the
  # current integration version. They are only associated with the hook for the
  # integration itself.
  #
  # The #default_events= method is only additive when it comes to the
  # integration's hook's events. The #integrator_events= method must also remove
  # events that should no longer be subscribed, without clobbering any default
  # events.
  #
  # event_names - An Array of event names.
  #
  # Returns an Array of subscribed event names.
  def integrator_events=(event_names)
    # Include only integrator events.
    event_names &= Integration::Events::INTEGRATOR_EVENTS

    # In the event that integrator events are set
    # on a new record, there won't be a hook even if there
    # are hook attributes.
    #
    # Build a hook so that if there are failures
    # they show up in the UI.
    if event_names.any? && new_record? && hook.nil?
      build_hook # The other default settings are set at before_validation
    end

    return [] if hook.nil?

    subscribed = integrator_events
    to_add = event_names - subscribed
    to_remove = subscribed - event_names

    transaction do
      T.must(hook).add_events(to_add)
      T.must(hook).remove_events(to_remove)
    end
  end

  delegate :note, to: :latest_version

  def note=(note)
    current_version.note = note
  end

  # Public: The String single_file_name that this integration
  # has access too.
  #
  # Example
  #   single_file_name
  #   # => ".github"
  #
  # Returns a String.
  delegate :single_file_name, to: :latest_version

  # Public: Set the String file name that maps to a
  # single file in the repository.
  #
  # file_name - The String mapping to the file name.
  #
  # Returns a String.
  def single_file_name=(file_name)
    return if file_name.blank?
    transaction { current_version.single_file_name = file_name }
  end

  delegate :single_file_paths, to: :latest_version

  # Public: Set the String file paths that maps to
  # single files in the repository.
  #
  # single_files - The Array of String file paths.
  #
  # Returns an array of IntegrationSingleFiles.
  def single_file_paths=(single_files)
    current_version.single_file_paths = single_files
  end

  def user_token_expiration_enabled?
    user_token_expiration
  end

  # Public: Give this integration access to repositories
  #
  # target        - The User or Organization account that the application is
  #                 being installed on.
  # repositories: - An Array of Repositories to include in the installation.
  # installer:    - The User performing the installation.
  # version       - The IntegrationVersion used for permissions and events.
  #                 Defaults to the `latest_version`.
  # trigger_id    - id of the integration_install_trigger that led to this
  #                 installation
  #
  # reinstalling_during_repository_transfer - A boolean flag used to indicate
  #                                         whether or not we're reinstalling an app
  #                                         during repository transfers
  #
  # Returns an IntegrationInstallation::Creator::Result.
  def install_on(target, repositories:, installer:, version: self.latest_version, trigger_id: nil, reinstalling_during_repository_transfer: false, entry_point:)
    options = {
      repositories:      repositories,
      installer:         installer,
      version:           version,
      trigger_id:        trigger_id,
      entry_point:       entry_point,
      reinstalling_during_repository_transfer: reinstalling_during_repository_transfer,
    }

    IntegrationInstallation::Creator.perform(self, target, **options)
  end

  # Public: Is this integration installed on the specified target?
  #
  # target - A User or Organization account.
  #
  # Returns a Boolean.
  def installed_on?(target)
    installations_on(target).exists?
  end

  # Public: The installations for the specified target.
  #
  # target - A User or Organization account.
  #
  # Returns a AR scope of the installations for the target
  def installations_on(target)
    installations.with_target(target)
  end

  # Public: Is this integration a globally enabled app?
  #
  # Returns a Boolean
  def enabled_global_app?
    Apps::Internal.capable?(:installed_globally, app: self) &&
      !GitHub.flipper[:disabled_global_apps].enabled?(self)
  end

  # Public: Is this integration owned by a user?
  #
  # Returns a Boolean
  def user_owned?
    owner_type == "User" && owner.type == "User"
  end

  # Public: Is this integration owned by a organization?
  #
  # Returns a Boolean
  def organization_owned?
    owner_type == "User" && owner.type == "Organization"
  end

  # Public: Is this integration owned by an enterprise?
  #
  # Returns a Boolean
  def enterprise_owned?
    owner_type == "Business"
  end

  # Public: Boolean flag to tell if an integration is owned by GitHub.
  #
  # Returns true if this integration is owned by GitHub, Inc.
  def github_owned?
    owner_id == GitHub.trusted_apps_owner_id
  end

  def adminable_by?(actor)
    owner.adminable_by?(actor)
  end

  # Public: Can the avatar of this Integration be edited by the given actor?
  #
  # actor - User to check for ability to edit the avatar.
  #
  # Returns Boolean
  def avatar_editable_by?(actor)
    manageable_by?(actor)
  end

  # Public: Can the IP allow list of this Integration be managed by the given actor?
  #
  # actor - User to check for ability to manage the IP allow list.
  #
  # Returns Boolean
  def ip_allowlist_manageable_by?(actor)
    manageable_by?(actor)
  end

  # Public: Can this Integration be managed by the given actor?
  #
  # actor - User to check for ability to manage the Integration.
  #
  # Returns Boolean
  def manageable_by?(actor)
    return false if actor.is_a?(Bot)

    ::Permissions::Enforcer.authorize(
      action: :manage_app,
      actor: actor,
      subject: self,
    ).allow?
  end

  # Public: Generate and persist a new public key for the integration.
  def generate_key(creator:)
    self.public_keys.transaction do
      self.public_keys.create(creator: creator)
    end
  end

  # Public: Determine whether or not a given user can view details about
  # an integration including description.
  #
  # For public integrations this is always true. For private integrations
  # this is only true for the owning user or a member of the owning organization.
  #
  # Returns a Boolean.
  def readable_by?(actor)
    async_readable_by?(actor).sync
  end

  def async_readable_by?(actor)
    # Preloading because there's a flipper check in public_visibility
    # for :enterprise_owned_app_management
    #
    # Can be moved back to the if/else below when removing the flag
    owner = async_owner.sync

    return Promise.resolve(true) if public_visibility?
    if actor.respond_to?(:integration)
      # an App viewing itself
      return Promise.resolve(true) if actor.integration == self
    end

    if owner.respond_to?(:async_member?)
      owner.async_member?(actor)
    else
      owner.async_adminable_by?(actor)
    end
  end

  # Public: Determine whether or not a given user is allowed to install the
  # integration.
  #
  # For public integrations this is true for signed in users.
  #
  # For private integrations:
  #   * if owned by a user: this is only true for the owning user.
  #   * if owned by an organization: this is only true for an admin of the owning organization,
  #     or a user who can admin any repositories of the owning organization
  #   * if owned by an enterprise: this only true for an admin of the owning enterprise.
  #
  # For internal integrations: this is only true if the owner is an enteprise and the user is an admin of an organization in the enterprise.
  #
  # Returns a Boolean.
  def installable_by?(user)
    return false unless user
    return true if public_visibility?

    # return early since the target could be an org and not the owner
    if internal_visibility?
      return true if owner.owner?(user) || owner.user_is_owner_of_owned_org?(user)
    end

    installable_on_by?(target: owner, actor: user)
  end

  # Public: Determine whether or not a given user is allowed to install the
  # integration on the given target.
  #
  # Returns an instance of Integration::Permissions::Result.
  def installable_on_by(target:, actor:, repository_ids: nil)
    options = {
      integration: self,
      actor:       actor,
      action:      :install,
      target:      target,
      version:     latest_version,
    }

    if repository_ids
      options[:repository_ids] = repository_ids
      options[:repository_selection] = Integration::Permissions::RepositorySelection::Subset
    else
      options[:repository_selection] = Integration::Permissions::RepositorySelection::Any
    end

    Integration::Permissions.check(**options)
  end

  # Public: Determine whether or not a given user is allowed to install the
  # integration on the given target.
  #
  # Returns a Boolean.
  def installable_on_by?(target:, actor:, repository_ids: nil)
    check = installable_on_by(target: target, actor: actor, repository_ids: repository_ids)
    check.permitted?
  end

  # Can the given user install thie GitHub App
  # on all repositories on the target account.
  #
  # Returns Boolean.
  def installable_on_all_repositories_by?(target:, actor:)
    Integration::Permissions.check(
      integration:          self,
      actor:                actor,
      action:               :install,
      target:               target,
      repository_selection: Integration::Permissions::RepositorySelection::All,
      version:              latest_version,
    ).permitted?
  end

  # Public: Determine whether the given user can request an installation
  # of this GitHub App on this target account?
  #
  # Returns an instance of Integration::Permissions::Result.
  def requestable_on_by(target:, actor:)
    Integration::Permissions.check(
      integration: self,
      actor:       actor,
      action:      :request_installation,
      target:      target,
    )
  end

  # Can the given user request installation
  # of this GitHub App on this target account?
  #
  # Returns a Boolean.
  def requestable_on_by?(target:, actor:)
    check = requestable_on_by(target: target, actor: actor)
    check.permitted?
  end

  # Public: Determine whether or not the integration is installable on a given
  # account.
  #
  # If the Integration is owned by an EMU organization, it can only be installed within the Enterprise.
  #
  # For public integrations this is true for any account.
  #
  # For private integrations, this is only true for the owning account.
  #
  # For internal integrations, this is true for the owning business and the
  # organizations of the owning business.
  #
  # Returns a Boolean.
  def installable_on?(target)
    return false if suspended?

    if target&.user? && target.is_enterprise_managed?
      return false unless Apps::Internal.capable?(:installable_on_emus, app: self)
    end

    # Integrations owned by EMUs cannot be installed outside of the Enterprise
    if is_enterprised_managed?(owner) && GitHub.flipper[:integration_installable_on_with_emus_check].enabled?(self)
      # Return false early if the target isn't Enterprises Managed as we already know
      # there is a mismatch between the owning Enterprise and the target Enterprise.
      return false unless is_enterprised_managed?(target)
      # Compare the Integration owner and the target to ensure that both are managed by
      # the same Enterprise
      target_business = enterprise_managed_business_for(target)
      owner_business = enterprise_managed_business_for(owner)
      return false unless owner_business == target_business
    end

    if target.is_a?(Business) && target.feature_enabled?(:enterprise_app_installation_management)
      return true if connect_app?
      # If this App doesn't request any Enterprise permissions it can't be
      # installed on an Enterprise
      return false if Business::Resources.filter(default_permissions).empty?
    end

    return false unless valid_target?(target)
    return true if public_visibility?
    return true if private_visibility? && (github_owned? || connect_app?)

    if internal_visibility?
      # owner will be a business
      return true if target.is_a?(Organization) && target.business == owner
      return false if target.is_a?(User)
    end

    target == owner
  end

  # Public: Can this integration request the installer to also authorize the
  # user's account via OAuth?
  #
  # Note: Based on this model's internal boolean attribute `request_oauth_on_install`.
  #
  # Returns a Boolean.
  def can_request_oauth_on_install?
    can_send_callback_requests? && request_oauth_on_install?
  end

  # Public: Can this App be deleted? Prevents the App being
  # deleted in cases where assocated marketplace listing has subs.
  #
  # - Apps with marketplace listing subs can't be deleted
  #
  def can_delete?
    if GitHub.flipper[:marketplace_allow_deleting_apps_with_no_active_subscriptions].enabled?
      return false if marketplace_listing&.subscription_items&.active.present?
    else
      return false if marketplace_listing&.subscription_items.present?
    end
    true
  end

  # Used for GitHub::UserContent
  def body
    description
  end

  include Instrumentation::Model

  def event_prefix
    :integration
  end

  def event_payload
    {}.tap do |payload|
      payload[:integration]       = self
      payload[:app]               = self
      payload[:name]              = name
      payload[:slug]              = slug
      payload[owner.event_prefix] = owner
    end
  end

  def event_context(prefix: :app)
    {
      "#{prefix}".to_sym    => name,
      "#{prefix}_id".to_sym => id,
    }
  end

  def default_user_token_expiration_enabled
    bool = if defined?(@user_token_expiration_enabled)
      ActiveModel::Type::Boolean.new.cast(user_token_expiration_enabled)
    else
      true
    end

    self.user_token_expiration = bool
  end

  def instrument_creation
    GitHub.dogstats.increment("integration", tags: ["action:create"])
    instrument :create
  end

  def instrument_deletion
    instrument :destroy
  end

  def instrument_suspension
    instrument :suspend, suspended_reason: self.suspended_reason
  end

  def instrument_unsuspension
    instrument :unsuspend
  end

  def instrument_github_app_manager(member, action:)
    case action
    when :grant
      instrument :manager_added, manager: member
    when :revoke
      instrument :manager_removed, manager: member
    end
  end

  # Public: Can this App ownership be transfered? Prevents the App being
  # transferred in cases where a private App is already installed on the
  # owner account.
  #
  # @return [Boolean]
  def can_transfer_ownership?
    return false if enterprise_owned?
    return true if public_visibility?
    return true unless owner.feature_enabled?(:block_private_installed_app_ownership_transfer)

    installations.none?
  end

  def pending_transfer?
    transfer.present?
  end

  # Public: Whether to include this app in marketplace searches; if the app has
  #         been publicly listed, then defer to the listing instead.
  def include_in_marketplace_searches?
    return false unless self.id.present?

    listing = Marketplace::Listing.find_by(listable: self)
    !listing.present? || listing.draft?
  end

  # Public: Get an image URL for the logo that best represents this app, ignoring the current
  # user and whether this app is listed in the Marketplace or not.
  def preferred_avatar_url(size: 80)
    return canonical_avatar_url if canonical_avatar_url
    return primary_avatar_url(size) if primary_avatar
    UrlHelpers.app_identicon_path(IDENTICON_TYPE, slug)
  end

  def primary_avatar_path
    return @primary_avatar_path if defined?(@primary_avatar_path)
    return @primary_avatar_path = "/in/#{id}" if primary_avatar

    # Back up to owner's avatar
    user = owner
    user ||= User.ghost

    @primary_avatar_path = user.primary_avatar_path
  end

  # Public: Returns the canonical Dotcom avatar url for Proxima synced apps
  # returns nil for non-synced and non-Proxima apps
  def canonical_avatar_url
    ProximaAppSynchronization.canonical_avatar_url_for(self)
  end

  def tenant_slug_for_avatar
    return "" unless GitHub.multi_tenant_enterprise?

    # Integrations always have bots associated with them
    T.must(bot).tenant_slug_for_avatar
  end

  def primary_avatar_url(size = nil)
    return super if size.nil? || primary_avatar

    # The User Avatar needs to be double the
    # given size
    size *= 2

    super
  end

  def public_app_path(actor: nil)
    generate_public_app_path(owner, actor)
  end

  def async_public_app_path(actor: nil)
    async_owner.then do |owner|
      generate_public_app_path(owner, actor)
    end
  end

  # Public: Transfers the integration to a target user/organization and deletes
  # any transfer requests for the integration.
  #
  # target     - The User or Organization to transfer the integration to.
  # requester  - The User requesting the transfer.
  # responder  - The User completing the transfer.
  #
  # Returns a Boolean.
  def transfer_ownership_to(target, requester:, responder:, entry_point:)
    return false unless can_transfer_ownership?
    return false if owner.feature_enabled?(:block_emu_transfers_to_non_emu_target) && !valid_target?(target)

    instrument :transfer, \
      transfer_from: owner,
      transfer_to: target,
      requester: requester,
      responder: responder

    self.owner = target

    transaction do
      result = remove_app_manager(entry_point: entry_point)

      if result.failure?
        false
      else
        save!
        regenerate_hook! if hook.present?
        T.must(transfer).destroy if transfer

        true
      end
    end
  end

  def keep_old_avatar?
    false
  end

  # Internal: can we send requests to this integration's callback_url?
  def can_send_callback_requests?
    application_callback_urls.exists?
  end

  # Public: check if a url is a direct match of the callback_url.
  #
  # This is used in OauthUtil and is implemented to match OauthApplication logic.
  #
  # Returns a boolean.
  def callback_url_direct_match?(url)
    return true if application_callback_urls.exists?(url: url)

    if Apps::Internal.capable?(:proxima_first_party_sync, app: self)
      return application_callback_urls.map(&:url).any? { |u| u.match?(url) }
    end

    false
  end

  # Public: URI version of callback_url.
  #
  # Used in OauthUtil, provided for parity between OauthApps and GitHub Apps.
  #
  # Returns nil or an Addressable::URI
  def callback_uri
    return nil unless can_send_callback_requests?

    Addressable::URI.parse(callback_url)
  end

  def callback_urls
    application_callback_urls.order(id: :asc).pluck(:url)
  end

  def raw_callback_urls
    application_callback_urls.order(id: :asc).pluck(:raw_url)
  end

  def callback_url
    application_callback_urls.order(id: :asc).first&.url
  end

  def raw_callback_url
    application_callback_urls.order(id: :asc).first&.raw_url
  end

  # Internal: does this integration have additional setup after installation?
  def additional_setup_required?
    setup_url.present?
  end

  def outdated_installations(version = latest_version)
    installations.where("integration_installations.integration_version_number < ?", version.number)
  end

  def installations_with_version(version_number)
    installations.where("integration_installations.integration_version_number = ?", version_number)
  end

  def async_installation_for(resource)
    case resource
    when Repository
      Platform::Loaders::IntegrationInstallation::Repository.load(resource, id)
    else
      Promise.resolve(nil)
    end
  end

  # Public: Boolean flag to tell if an integration is used for GitHub Connect
  #
  # Returns true if this integration has a corresponding GitHub Connect
  # EnterpriseInstallation.
  def connect_app?
    enterprise_installation.present?
  end

  # Public: Boolean flag to tell if an application uses Oauth scopes.
  #
  # Returns false for all Integrations.
  def uses_scopes?
    false
  end

  # Public: Boolean flag to tell if an integration installation
  # requires a verified email from user
  #
  def verified_email_required?(actor)
    return true if actor.nil?
    can_request_oauth_on_install? && actor.should_verify_email?
  end

  # Indicates if the Integration should be exempted from organization
  # 3rd party OAuth Application policies.
  #
  # Returns a Boolean.
  def third_party_oap_exempt?
    true
  end

  # Indicates if the Integration should be exempted from organization
  # OAuth Application policies.
  #
  # Returns a Boolean.
  def oap_exempt?
    true
  end

  # first-party oauth apps can be blocked by orgs,
  # but GitHub apps cannot
  def blockable_client_app?
    false
  end

  # Indicates if third party restrictions can be applied to this integration.
  # False for all Integrations.
  def third_party_restrictions_applicable?
    false
  end

  # Public: Integer state of the integration
  # column :state
  #   :active           - Active and allowed to make requests.
  #   :suspended        - Suspended from installation or creating oauth accesses
  #                       due to abuse or security concerns.
  enum :state, { active: 0, suspended: 1 }

  belongs_to :user_suspended_by, class_name: "User"

  # Public: validates that an Internal app cannot be suspended
  # unless the `danger_zone_permitted` capability is enabled.
  def validate_state
    return if Apps::Internal.capable?(:danger_zone_permitted, app: self)

    errors.add(:state, "cannot be suspended")
  end

  # Public: Suspends integration so that it cannot be installed or create oauth accesses
  def suspend(actor:, reason:)
    return true if self.suspended?
    return false unless actor&.site_admin?

    update(state: :suspended, suspended_reason: reason, user_suspended_by_id: actor.id, suspended_at: Time.now.utc)
  end

  # Public: Unsuspends integration so that it can be installed and create oauth accesses
  def unsuspend(actor:)
    return false unless actor&.site_admin?

    update(state: :active, suspended_reason: nil, user_suspended_by_id: nil, suspended_at: nil)
  end

  # Public: Suspends all integrations for a given owner
  def self.suspend_all_for_owner(actor:, owner:, reason:)
    return false unless actor&.site_admin? && reason.present?

    Integration
      .where(owner: owner, state: :active)
      .update(:all, state: :suspended, suspended_reason: reason, user_suspended_by_id: actor.id, suspended_at: Time.now.utc)
  end

  # Public: Unsuspends all integrations for a given owner
  def self.unsuspend_all_for_owner(actor:, owner:)
    return false unless actor&.site_admin?

    Integration
      .where(owner: owner, state: :suspended)
      .update(:all, state: :active, suspended_reason: nil, user_suspended_by_id: nil, suspended_at: nil)
  end

  def strict_callback_url_validation?
    application_callback_urls.many?
  end

  def repository_installation_required?(target, version = latest_version)
    return false unless version.any_permissions_of_type?(Repository)

    relevant_permissions = version.permissions_relevant_to(target)
    return false if relevant_permissions.empty?

    repository_permissions = version.permissions_of_type(Repository)

    relevant_permissions.any? do |permission, _action|
      repository_permissions.include?(permission)
    end
  end

  def repository_permissions_only?(version = latest_version)
    version.all_permissions_of_type?(Repository)
  end

  def abuse_limits_multiplier
    ActiveRecord::Base.connected_to(role: :reading) do
      # https://github.com/github/ecosystem-api/issues/1860#issuecomment-588390136
      if Apps::Internal.capable?(:abuse_limit_multiplier, app: self)
        base_multiplier = TRUSTED_ABUSE_LIMIT_MULTIPLIER
        # These flags are here in case we need to limit Action's traffic to
        # creating new access tokens at the top of the hour.
        # See https://github.com/github/availability/issues/1371
        #
        # On production, the app is ID 15368
        # https://admin.github.com/stafftools/users/github/apps/github-actions
        #
        # https://admin.github.com/devtools/feature_flags/disable_abuse_limits_multipler
        # https://admin.github.com/devtools/feature_flags/decrease_abuse_limits_multiplier
        if GitHub.flipper[:disable_abuse_limits_multiplier].enabled?(self)
          1
        elsif GitHub.flipper[:decrease_abuse_limits_multiplier].enabled?(self)
          base_multiplier / 2
        elsif GitHub.flipper[:increase_abuse_limits_multiplier].enabled?(self)
          base_multiplier * 1.5
        else
          base_multiplier
        end
      else
        1
      end
    end
  end

  def can_set_loopback_webhook?
    Apps::Internal.capable?(:can_set_loopback_webhook, app: self)
  end

  def self.launch_github_app?(id)
    GitHub.launch_github_app&.id == id
  end

  def self.launch_lab_github_app?(id)
    GitHub.launch_lab_github_app&.id == id
  end

  def launch_github_app?
    self.class.launch_github_app?(self.id)
  end

  def launch_lab_github_app?
    self.class.launch_lab_github_app?(self.id)
  end

  def dependabot_github_app?
    GitHub.dependabot_github_app&.id == id
  end

  # Internal: Determine if the integration is the GroupSyncer service
  def group_syncer_github_app?
    return false if GitHub.group_syncer_github_app_id.to_i.zero?
    GitHub.group_syncer_github_app_id.to_i == self.id
  end

  def accepts_secrets_from_users?
    # Only the prod app has secrets. In lab, we read prod's secrets.
    launch_github_app?
  end

  # Returns true if we should allow this integration to create multiple
  # check suites at any given commit SHA.
  def multiple_check_suites_per_sha_enabled?
    # if this is changed, update the find_or_create_for_integrator test
    launch_github_app? || launch_lab_github_app?
  end

  def validate_client_secret(plaintext)
    return false if plaintext.blank?
    hash = IntegrationClientSecret.hash_for(plaintext)

    if client_secret = client_secrets.find_by(secret_hash: hash)
      client_secret.access
      true
    end
  end

  def generate_client_secret(creator:, bypass_secrets_limit: false)
    secret = self.client_secrets.transaction do
      self.client_secrets.create(creator: creator, bypass_secrets_limit: bypass_secrets_limit)
    end
    instrument :generate_client_secret
    secret
  end

  def max_client_secrets_reached?
    client_secrets.count >= IntegrationClientSecret::MAX_SECRETS
  end

  # TODO: Pass entry_point kwarg to job once method signature has been shipped
  # in https://github.com/github/github/pull/278181.
  def async_revoke_tokens(entry_point: nil)
    RemoveIntegrationTokensJob.perform_later(self, created_before: Time.now.iso8601)
  end

  def platform_type_name
    "App"
  end

  # TODO: Setting this to a hard-coded value to unblock progress of getting the
  # quota based rate limiter shipped.
  def rate_limit
    10_000
  end

  def self.ghost
    GhostGitHubApp.instance
  end

  def ghost?
    self == Integration.ghost
  end

  def subscribable_hook?
    hook&.active?
  end

  def active_and_subscribable?
    active? && subscribable_hook?
  end

  def fingerprint
    Digest::SHA256.hexdigest("#{id}:#{updated_at}:#{latest_version.id}")
  end

  def synchronization_fingerprint
    canonical = [
      fingerprint,
      application_callback_urls.map(&:updated_at).join,
      owner.display_login, # in case there's an ownership transfer
      owner.primary_avatar_path, # the main owner difference we want to sync
    ].join

    Digest::SHA256.hexdigest(canonical)
  end

  def agent_enabled?
    owner.feature_enabled?(:copilot_extendable)
  end

  def agent_disableable?
    owner.feature_enabled?(:copilot_extension_disableable)
  end

  def agent_configured?(version = latest_version)
    return false unless integration_agent.present?

    permissions = version.permissions_of_type(User).keys
    permissions.include?(COPILOT_PERMISSION)
  end

  def target_for_conditional_access
    owner
  end

  private

  def generate_tenant_scoped_url?(value)
    ::ProximaAppRequest::TenantScopedUrl.should_generate?(app: self, url: value)
  end

  # Private: In the event a hook is being created,
  # set the hook name and content_type since these
  # are not available to the creator of the Integration.
  #
  # Returns true.
  def set_default_hook_attributes
    return true if hook.nil?
    return true unless T.must(hook).new_record?

    T.must(hook).name = "web"
    T.unsafe(hook).content_type = "json"

    true
  end

  def normalize_bgcolor
    return unless bgcolor.present?

    self.bgcolor = bgcolor.sub(/\A#/, "")
  end

  def slug_is_not_reserved
    if RESERVED_SLUGS.include?(slug)
      errors.add(:name, "is a reserved word and cannot be used")
    end
  end

  # Private: validate slug does not match an existing owners's login/slug
  # - This protects against name squatting
  # - Owners can create apps that match their User/Organization login or Business slug
  def slug_is_not_existing_owner
    return unless owner.present?
    return if @skip_slug_owner_check && GitHub.enterprise?

    owner_slug = case owner
    when Business
      owner.slug
    when User
      owner.login.parameterize
    end

    return if owner_slug == slug

    case owner
    when Organization
      return if owner.business&.slug == slug
    when User
      return if owner.owned_organizations.where(login: slug).exists?
      return if owner.businesses(membership_type: :admin).where(slug: slug).exists?
    end

    errors.add(:name, "is reserved for the account @#{slug}") if User.where(login: slug).exists?
    errors.add(:name, "is reserved for the account #{slug}")  if Business.where(slug: slug).exists?
  end

  # Private: remove the manage_app grant from the given App manager.
  #
  # Returns a Permissions::GrantResult.
  def remove_app_manager(entry_point:)
    results = ::Permissions::Enumerator.actor_ids_with_permission(
      action: :manage_app,
      subject_id: id,
    ).map do |actor_id|
      ::Permissions::Granter.revoke(
        action: :manage_app,
        actor_id: actor_id,
        subject_id: id,
        entry_point: entry_point,
      )
    end

    return ::Permissions::GrantResult.failure! if results.any? { |result| result.failure? }
    ::Permissions::GrantResult.success!
  end

  def restrict_names_with_github
    return unless name.present? && owner
    return if github_owned?
    return if owner.is_a?(User) && owner.employee? && owner.site_admin?
    return if @skip_restrict_names_with_github_validation
    return if !new_record? && name.start_with?("GitHub Enterprise ") && connect_app?

    if name_starts_with_github?
      errors.add(:name, "should not begin with 'GitHub' or 'Gist'")
    end

    if name_implies_github_affiliation?
      errors.add(:name, "should not imply the integration is from GitHub")
    end

    if name_parameterizes_to_start_with_github?
      errors.add(:name, "should not generate slugs that begin with 'GitHub' or 'Gist'")
    end

    if name_parameterizes_to_imply_github_affiliation?
      errors.add(:name, "should not generate slugs that imply the integration is from GitHub")
    end

  end

  def restrict_names_with_urls
    if name.present? && name_includes_urls?
      errors.add(:name, "should not include any URLs")
    end
  end

  # Private: validate slug is
  # - present (if an invalid name prevented slug generation)
  # - less than or equal to the Bot::MAX_SLUG_LENGTH limit
  # - not already in use
  def validate_integration_slug
    return unless name.present?

    unless slug.present?
      revert_slug
      return errors.add(:name, "must contain at least one alphanumeric character")
    end

    if slug.length > Bot::MAX_SLUG_LENGTH
      revert_slug
      return errors.add(:name, "cannot be longer than #{Bot::MAX_SLUG_LENGTH} characters")
    end

    check_existence = if GitHub.flipper[:owner_scoped_github_apps].enabled?(owner)
      Integration.exists?(owner: owner, slug: slug)
    else
      Integration.exists?(slug: slug)
    end

    if self.slug_changed? && check_existence
      revert_slug
      return errors.add(:name, "is already taken")
    end

    if slug.include? "_"
      revert_slug
      errors.add(:name, "cannot contain underscores")
    end
  end

  # Private: validate url is a String and valid URL.
  def validate_integration_url
    unless url.is_a?(String)
      return errors.add(:url, INVALID_URL_MESSAGE)
    end

    unless IntegrationUrl.valid_application_url?(url)
      errors.add(:url, INVALID_URL_MESSAGE)
    end
  end

  # Private: validate setup_url is a valid URL and is safe to redirect to.
  def validate_setup_url
    return unless setup_url.present?

    unless setup_url.is_a?(String)
      return errors.add(:setup_url, INVALID_URL_MESSAGE)
    end

    unless IntegrationUrl.valid_application_url?(setup_url)
      errors.add(:setup_url, INVALID_URL_MESSAGE)
    end
  end

  def validate_permission_actions
    return unless invalid_permissions.present?

    invalid_permissions.each do |permission, action|
      next if Ability.valid_action?(action)
      message = "'#{permission}' has an invalid action: '#{action}'."
      errors.add(:permission, message)
    end
  end

  def generate_bot_slug
    return unless slug.present?


    bot_login = if GitHub.flipper[:owner_scoped_github_apps].enabled?
      SecureRandom.hex(17)
    else
      slug
    end
    build_bot(login: bot_login) if bot.nil?

    T.must(bot).slug = slug
  end

  def generate_alias_slug
    return unless slug.present?

    if GitHub.flipper[:owner_scoped_github_apps].enabled?(owner)
      self.alias&.destroy
    else
      self.alias || build_alias
      T.must(self.alias).slug = slug
    end
  end

  def generate_slug
    return unless name.present?
    return if new_record? && @skip_generate_slug && slug.present?
    self.slug = name.parameterize
  end

  def revert_slug
    self.slug = T.must(self.slug_was)
  end

  def update_latest_version
    latest_version.save
  end

  # Private: Get the current version either used when creating
  # or updating an integration's permissions.
  #
  # Returns an IntegrationVersion
  def current_version
    if new_record?
      @version = latest_version unless defined?(@version)
    else
      @version = versions.build if !defined?(@version)
      @version = versions.build if @version.persisted?
    end

    @version
  end

  def regenerate_hook!
    events = T.must(hook).events
    config = T.must(hook).config
    active = T.must(hook).active

    T.must(hook).destroy!
    self.hook = nil

    build_hook(name: "web", content_type: "json")

    T.must(hook).config = config
    T.must(hook).add_events(events)
    T.must(hook).active = active
    T.must(hook).save!
  end

  # Because a child version does all of the
  # validation for permissions, events, and
  # single_file_name. We need to format the errors
  # so that they look alright for the integration.
  def format_version_error_messages
    return if self.errors.empty?
    version_error_prefix = %r{\A(latest_version|versions)\.}

    error_names = self.errors.attribute_names

    error_names.each do |key|
      next unless key.to_s.match?(version_error_prefix)
      new_key = key.to_s.gsub(version_error_prefix, "").to_sym

      self.errors[key].each { |error| errors.add(new_key, error) }
      errors.delete(key.to_sym)
    end
  end

  def setup_url_missing?
    setup_on_update && setup_url.blank? && application_callback_urls.none?
  end

  def prevent_setup_on_update
    self.setup_on_update = false
  end

  # There are special exceptions where we need to delete the Bot in the
  # background. This allows that override.
  def destroy_bot_async
    T.must(bot).async_destroy
  end

  def destroy_bot
    T.must(bot).destroy
  end

  def generate_public_app_path(app_owner, actor)
    owner_scoping_enabled = GitHub.flipper[:owner_scoped_github_apps].enabled? || actor.try(:feature_enabled?, :owner_scoped_github_apps)
    return "" if self.slug.blank?
    return UrlHelpers.alias_app_path(self) unless owner_scoping_enabled

    if enterprise_owned?
      UrlHelpers.business_app_path(app_owner, self)
    elsif ProximaAppSynchronization.synchronized?(self)
      UrlHelpers.external_app_path(self)
    else
      UrlHelpers.user_app_path(app_owner, self)
    end
  end
end
