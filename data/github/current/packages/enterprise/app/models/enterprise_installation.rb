# typed: true
# frozen_string_literal: true

class EnterpriseInstallation < ApplicationRecord::Domain::Users
  include Instrumentation::Model
  include GitHub::Relay::GlobalIdentification
  include GitHub::Validations

  VALID_OWNER_TYPES = %w(User Business).freeze
  MINIMUM_SERVER_ID_REQUIRED_VERSION = 2.17
  GS1_TOKEN_FORMAT_REQUIRED_VERSION = 3.2
  GITHUB_APP_ICON_BACKGROUND_COLOR = "5A32A3".freeze

  TOKEN_TTL = 1.week

  belongs_to :integration, dependent: :destroy
  # This is the owner that the enterprise installation belongs to
  belongs_to :owner, polymorphic: true
  has_many :user_accounts, class_name: "EnterpriseInstallationUserAccount"
  destroy_dependents_in_background :user_accounts
  has_many :user_accounts_uploads, class_name: "EnterpriseInstallationUserAccountsUpload"
  destroy_dependents_in_background :user_accounts_uploads
  has_many :enterprise_contributions

  validates_presence_of :owner
  validates :owner_type, inclusion: VALID_OWNER_TYPES
  validates_presence_of :host_name
  validates :host_name, unicode3: true
  validates_presence_of :license_hash
  validates_presence_of :customer_name
  validates :customer_name, unicode3: true

  # In the very unlikely event that an installation being created by manual
  # license usage upload cannot have the public key read from the license file,
  # allow license_public_key to be an empty string, but not nil, to satisfy
  # the NOT NULL constraint on the column.
  validates :license_public_key, exclusion: { in: [nil], message: "cannot be nil" }

  validate :validate_server_id

  serialize :features, coder: JSON

  after_create_commit :instrument_creation
  after_update_commit :instrument_updated
  after_destroy_commit :instrument_deletion

  after_commit :update_business_license_usage

  before_destroy :clear_enterprise_contributions

  scope :for_query, ->(query) {
    safe_query = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.downcase)
    return scoped unless safe_query.present?

    where <<-SQL, query: "%#{safe_query}%"
      enterprise_installations.customer_name LIKE :query
      OR enterprise_installations.host_name LIKE :query
    SQL
  }

  attr_accessor :public_key

  def last_user_accounts_upload
    user_accounts_uploads.order("created_at desc").limit(1).first
  end

  def self.for_github_app(app)
    where(integration_id: app.id).first
  end

  def self.blocked?(license_hash)
    # rubocop:todo GitHub/DoNotUseGlobalKv
    GitHub.kv.get("enterprise-installation-deny-#{license_hash}").value { nil }.present?
    # rubocop:enable GitHub/DoNotUseGlobalKv
  end

  def self.block(license_hash)
    GitHub.kv.set("enterprise-installation-deny-#{license_hash}", "true") # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def self.unblock(license_hash)
    GitHub.kv.del("enterprise-installation-deny-#{license_hash}") # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  def self.valid_server_id?(version, server_id)
    return true if version.nil?
    return true unless version.to_f >= MINIMUM_SERVER_ID_REQUIRED_VERSION

    server_id && server_id =~ /\A[a-f0-9\-]{36}\z/
  end

  # Public: Enqueue a background job to synchronize a hash of user accounts for
  # an Enterprise Server installation.
  #
  # business - The Business that owns the Enterprise Server installation.
  # installation - An optional existing EnterpriseInstallation for the sync.
  # upload_id - An Integer representing the ID of an
  # EnterpriseInstallationUserAccountsUpload pointing to a file containing the
  # data to be synced.
  # actor - The User performing the sync.
  #
  # Returns nothing.
  def self.synchronize_user_accounts_data(
    business:,
    installation: nil,
    upload_id:,
    actor:)
    SyncEnterpriseServerUserAccountsJob.perform_later \
      business, installation, upload_id, actor
  end

  def github_app?
    integration_id.present?
  end

  def target_for_conditional_access
    owner
  end

  def async_target_for_conditional_access
    async_owner
  end

  # Public: Is the installation connected to an Enterprise Server installation
  # via GitHub Connect?
  #
  # Returns true if discovered via GitHub Connect, otherwise false if the
  # installation was created as a result of license usage being uploaded.
  #
  # Returns a Boolean.
  alias_method :connected?, :github_app?

  def github_app
    @github_app = self.integration
  end

  def create_github_app(public_key = nil, public_key_creator = nil)
    name, slug = unique_app_name_and_slug_for(self.host_name)
    visibility = self.owner.is_a?(Business) ? "internal_visibility" : "private_visibility"

    app = self.create_integration!(
      owner: self.owner,
      name: name,
      slug: slug,
      url: UrlHelpers.home_url(host: host_name, protocol: host_protocol),
      default_permissions: {},
      visibility: visibility,
      application_callback_urls_attributes: [
        { url: UrlHelpers.settings_dotcom_user_callback_url(host: host_name, protocol: host_protocol) }
      ],
      skip_restrict_names_with_github_validation: true,
      skip_generate_slug: true,
      no_repo_permissions_allowed: true,
      bgcolor: GITHUB_APP_ICON_BACKGROUND_COLOR,
      user_token_expiration_enabled: false,
    )
    self.save
    if public_key
      app.public_keys.create(creator: public_key_creator, skip_generate_key: true, public_pem: public_key)
    end
    secret = app.generate_client_secret(creator: public_key_creator || User.ghost)
    [app, secret.secret]
  end

  # Public: Map a set of GitHub App permissions being requested to the
  # corresponding GitHub Connect features they grant access to.
  #
  # This method is the inverse of #required_github_app_permissions and is used
  # to map a set of permissions being requested to
  #
  # If you update this method, also update #required_github_app_permissions.
  #
  # permissions - A Hash of GitHub App permissions being requested.
  #
  # Returns an Array of Strings represeting GitHub App features.
  def features_for_github_app_permissions(permissions)
    return [] if permissions.blank?

    features = []
    features << "contributions" if permissions["external_contributions"] == :write
    features << "content_analysis" if permissions["enterprise_vulnerabilities"] == :read
    if permissions["contents"] == :read &&
      permissions["metadata"] == :read &&
      permissions["issues"] == :read
      features << "private_search"
    end
    features << "license_usage_sync" if permissions["enterprise_administration"] == :write

    features
  end

  # Private: Map a GitHub Connect feature to the required GitHub App permissions
  # for the feature.
  #
  # If you update this method, also update #features_for_github_app_permissions.
  #
  # This method allows features that need special permissions to trigger user
  # requests (via #update_permissions).
  #
  # feature - String representing a GitHub Connect feature.
  #
  # Returns a Hash.
  def required_github_app_permissions(feature)
    return { "external_contributions" => :write } if feature.to_s == "contributions"
    return { "enterprise_vulnerabilities" => :read } if feature.to_s == "content_analysis"
    return { "contents" => :read, "metadata" => :read, "issues" => :read } if feature.to_s == "private_search"
    return { "enterprise_administration" => :write } if feature.to_s == "license_usage_sync"
    {}
  end

  def has_required_github_app_permissions?(feature)
    return false if github_app.nil?

    required_github_app_permissions(feature).all? do |name, priv|
      github_app.default_permissions[name] == priv
    end
  end

  def github_app_permissions(features)
    features.map(&method(:required_github_app_permissions)).reduce({}, &:merge)
  end

  # If other features need additional flags, this could be refactored in the same
  # generalized style of #required_github_app_permissions
  def request_github_app_permissions_update(features)
    return if github_app.nil?
    github_app.reload

    permissions = github_app_permissions(features)
    if github_app.default_permissions != permissions
      version = github_app.versions.create(default_permissions: permissions)
      github_app.reload
      return version
    end
    nil
  end

  # Diff the proposed, or "latest" IntegrationVersion against the currently-active version.
  # Logic is similar to EnterpriseInstallation::FeatureUpdater#perform and #instrument_features_updated
  # Returns an IntegrationVersion::Differ::Result
  def github_app_latest_version_diff
    integration_previous_version = integration_installation.version
    github_app.latest_version.diff(integration_previous_version)
  end

  def integration_installation
    return if github_app.nil?

    github_app.installations.with_target(owner).first
  end

  def update_business_license_usage
    owner.update_license_usage if owner.is_a?(Business)
  end

  def clear_enterprise_contributions
    EnterpriseContribution.clear_installation_contributions(self)
  end

  def user_has_access?(user)
    return false if github_app.nil?

    user.oauth_authorizations.where(application_id: self.github_app.id).any?
  end

  # Public: Associate a user with their login on the remote installation
  #
  # user - the local (dotcom) user that we want to identify for that installation
  # login - their login on the remote GHE installation
  #
  # Raises an ArgumentError if login is not valid
  def set_login_for(user, login)
    unless login.match?(User::LOGIN_REGEX) &&
           login.length.between?(1, User::LOGIN_MAX_LENGTH)
      raise ArgumentError.new("Invalid login")
    end
    GitHub.kv.set(login_key(user), login) # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  # Public: Retrieve the user's login on the remote installation
  #
  # user - the local (dotcom) user whose GHE login we want to know
  #
  # Returns the login of that user on the remote GHE installation
  def login_for(user)
    GitHub.kv.get(login_key(user)).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  # Public: Retrieve the user's profile URL for the remote installation
  #
  # user - the local (dotcom) user whose GHE login we want to know
  #
  # Returns a URI for the profile (as long as we know their login)
  def profile_url_for(user)
    login = login_for(user)
    if login
      UrlHelpers.user_url(login, host: host_name, protocol: host_protocol)
    else
      UrlHelpers.home_url(host: host_name, protocol: host_protocol)
    end
  end

  def event_context(prefix: event_prefix)
    {
      "#{prefix}_id".to_sym => id,
      prefix.to_sym => host_name,
    }
  end

  def event_payload
    payload = {
      enterprise_installation: self,
      http_only: http_only,
      customer_name: customer_name,
    }

    payload[owner.event_prefix] = owner
    payload
  end

  def instrument_creation
    instrument :create
    GitHub.dogstats.increment("github_connect.connected")
    GitHub.dogstats.increment("github_connect.connect")
    GlobalInstrumenter.instrument("github_connect.connect", {
      enterprise_installation: self,
    })
  end

  def instrument_updated
    instrument :updated
    GlobalInstrumenter.instrument("github_connect.update_installation_info", {
      enterprise_installation: self,
    })
  end

  def instrument_deletion
    instrument :destroy
    GitHub.dogstats.decrement("github_connect.connected")
    GitHub.dogstats.increment("github_connect.disconnect")
    GlobalInstrumenter.instrument("github_connect.disconnect", {
      enterprise_installation: self,
    })
  end

  # Public: Instrument an update in the features enabled for the installation.
  #
  # features_enabled - Array of Strings representing the features being enabled.
  # features_disabled - Array of Strings representing the features being disabled.
  # actor - User that updated the GitHub Connect features.
  #
  # Returns nothing.
  def instrument_features_updated(features_enabled, features_disabled, actor)
    GlobalInstrumenter.instrument("github_connect.update_features", {
      enterprise_installation: self,
      features: features_enabled, # Note that the hydro schema uses 'features' to represent features enabled
      actor: actor,
      features_disabled: features_disabled,
    })
  end

  def platform_type_name
    "EnterpriseServerInstallation"
  end

  private

  def validate_server_id
    return if self.class.valid_server_id?(version, server_id)
    errors.add(:server_id, "is not a valid UUID")
  end

  # Private: key used to store an user's login on this installation
  def login_key(user)
    "enterprise-installation-user-login-app-#{self.id}.#{user.id}"
  end

  # Private: Return a name and slug for the integration app that mention the host,
  #          yet are valid and unique (by using matching suffixes when needed).
  #
  # E.g.: unique_app_name_and_slug_for("host.name") could return any of:
  #
  # - ["GitHub Enterprise for host.name",     "ghe-host-name-1"]
  # - ["GitHub Enterprise for host.name (2)", "ghe-host-name-2"]
  # - ["GitHub Enterprise for host.name (3)", "ghe-host-name-3"]
  #
  # and so on.
  def unique_app_name_and_slug_for(host)
    name = "GitHub Enterprise for #{host}".dup
    slug = "ghe-#{host.parameterize[0..22]}-1".gsub("--", "-")

    existing_names = Integration.where("name like ?", "#{name}%").pluck(:name)
    existing_slugs = Integration.where("slug like ?", "#{slug.chomp("-1")}%").pluck(:slug)

    while existing_names.include?(name) || existing_slugs.include?(slug) do
      if name.ends_with?(")")
        name.succ!
      else
        name << " (2)"
      end
      slug.succ!
    end

    [name, slug]
  end

  def host_protocol
    if http_only
      "http"
    else
      "https"
    end
  end
end
