# typed: true
# frozen_string_literal: true

# A Bot is a special type of User.
#
# A Bot only exists in conjunction with an Integration. A Bot performs actions
# on behalf of the Integration. Bots exist solely as a means for attributing
# these actions to an Integration.
#
# Would you like to know more? https://github.com/github/platform-archived/blob/master/proposals/integrations-2/bots-vs-users.md
class Bot < User
  has_one :integration
  validates_presence_of :integration

  has_one :marketplace_listing, through: :integration, disable_joins: true

  include Botable
  include Bot::RemoteAuthenticationDependency
  include PreloadableAttributes
  include GitHub::Memoizer

  attr_preloadable :marketplace_listing_url, :is_dependabot, :primary_avatar_path

  LOGIN_SUFFIX = "[bot]"
  LOGIN_REGEX = %r{
    \A                               # Beginning of String
    ([a-zA-Z0-9]+(?:-[a-zA-Z0-9]+)*) # [1] slug
    #{ Regexp.quote LOGIN_SUFFIX }   # string literal "[bot]"
    \z                               # End of String
  }x                                 # x: ignore whitepace
  MAX_SLUG_LENGTH = User::LOGIN_MAX_LENGTH - LOGIN_SUFFIX.length

  AUTHENTICATABLE_TYPES = %w[
    IntegrationInstallation
    ScopedIntegrationInstallation
    SiteScopedIntegrationInstallation
  ].freeze

  validate :validate_login

  before_validation :set_business_id, if: :validate_multi_tenant_business_id?

  after_create :preemptively_safelist

  # Public: Returns the IntegrationInstallation representing the bot's
  # current installation context.
  #
  # This installation context determines the bot's permissions. To perform any
  # privileged action (e.g., read the contents of a private repository, create a
  # commit status in a public repository), the bot's current installation
  # context must include permission to perform that action.
  alias :installation :ability_delegate

  def installation=(installation)
    self.ability_delegate = installation
  end

  attribute :login, :string

  delegate :github_owned?, to: :integration

  def async_slug
    if FeatureFlag.vexi.enabled?(:owner_scoped_github_apps, default: false)
      async_integration.then { |i| i&.slug }
    else
      slug
    end
  end

  # Internal: the slug for this Bot, based on:
  #
  # 1. the unsuffixed part of the login, in the case of legacy "globally
  #    unique" apps
  # 2. the slug of the integration associated with the bot, in the case of
  #    new-style apps that are unique by the combination of name and owner
  #
  # Returns a String
  def slug
    if FeatureFlag.vexi.enabled?(:owner_scoped_github_apps, default: false)
      async_slug.sync || slug_from_legacy_login # accounts for legacy apps that have been "orphaned" from their integration. See https://github.com/github/ecosystem-apps/issues/4909
    else
      slug_from_legacy_login
    end
  end

  # Internal: the slug for this legacy (globally unique) Bot, based the
  # unsuffixed part of the login.
  #
  # Returns a String
  def slug_from_legacy_login
    return unless login.present?

    match_data = login.match(LOGIN_REGEX)
    match_data && match_data[1]
  end

  def slug=(slug)
    if FeatureFlag.vexi.enabled?(:owner_scoped_github_apps, default: false)
      @display_login = nil # Bust memoization
    else
      self[:login] = "#{slug}#{LOGIN_SUFFIX}"
    end
  end

  def display_login
    custom_display_login || owner_scoped_display_login || login
  end

  def git_author_name
    display_login
  end

  def git_author_email
    StealthEmail.new(self).email(display_login)
  end

  # Internal: Get the string representing the Bot's key suitable for use in URLs.
  #
  # Example:
  #
  #   GitHub.enterprise?
  #   # => false
  #
  #   bot.marketplace_listing&.approved?
  #   # => true
  #
  #   bot.to_param
  #   # => "apps/stale"
  #
  #   ##################
  #
  #   GitHub.enterprise?
  #   # => true
  #
  #   bot.to_param
  #   # => "github-apps/stale"
  #
  #   ##################
  #
  #   FeatureFlag.vexi.enabled?(:owner_scoped_github_apps, default: false)
  #   # => true
  #
  #   bot.to_param
  #   # => "apps/github/stale"
  #
  # Returns a String.
  def to_param
    return @to_param if defined?(@to_param)

    # A Bot's slug may be nil in several cases:
    #
    # - Legacy bot + integration deleted (orphan) + :owner_scoped_github_apps FF enabled
    # - New bot + integration deleted (orphan) + :owner_scoped_github_apps FF enabled
    # - New bot + :owner_scoped_github_apps FF disabled
    #
    # We always attempt to use the associated app's slug, then try the
    # associated app's slug (to handle new bots when the FF is disabled) and
    # eventually falling back to the bot's login in the case of legacy bots.
    app_owner = async_integration.then { |i| i&.async_owner&.sync }.sync
    @to_param =
      if app_owner.present?
        # The Integration#public_app_path considers namespacing feature flags
        # and owner types (E.g. user/org/business)
        async_integration.sync&.public_app_path[1..-1]
      else
        safe_slug = slug || login
        UrlHelpers.alias_app_path(safe_slug)[1..-1]
      end
  rescue ActionController::UrlGenerationError
    @to_param = ""
  end

  # Internal: Returns the Marketplace listing path for the bot/app if it exists.
  def marketplace_listing_or_app_path
    async_marketplace_listing_or_app_path.sync
  end

  def marketplace_listing_url
    return @marketplace_listing_url if defined?(@marketplace_listing_url)
    @async_marketplace_listing_url = async_marketplace_listing_url.sync
  end

  # Internal: Returns the Marketplace listing url for the bot/app if it exists.
  def async_marketplace_listing_url
    Promise.resolve(@marketplace_listing_url) if defined?(@marketplace_listing_url)
    async_marketplace_listing_or_app_path.then do |marketplace_path|
      Addressable::URI.parse(GitHub.url).tap do |uri|
        uri.path = marketplace_path
      end.to_s
    end
  end

  def is_dependabot?
    return @is_dependabot if defined?(@is_dependabot)
    @is_dependabot = async_is_dependabot?.sync
  end

  def async_is_dependabot?
    Promise.resolve(false) unless GitHub.dependabot_github_app.present?
    Promise.resolve(@is_dependabot) if defined?(@is_dependabot)
    async_integration.then do |integration|
      integration.present? && integration.dependabot_github_app?
    end
  end

  def copilot_swe_agent?
    slug == Apps::Privileged::CopilotSWEAgent::SLUG
  end

  def ability_delegate
    installation
  end

  def to_query_filter
    agent = AgenticApp.agent_for_bot_id(id)
    agent.present? ? "@#{::AgenticApp.mention_token(agent)}" : self.class.query_filter_from_login(slug)
  end

  # Internal: converts a bot's login or slug to a string that's usable in a
  # search filter (e.g. author:app/hubot)
  def self.query_filter_from_login(login_or_slug)
    "app/#{login_or_slug.chomp(LOGIN_SUFFIX)}"
  end

  # Public: Implements the feature finder interface for Bots
  #
  # slug - The String slug.
  #
  # Returns a Bot
  # Raises ActiveRecord::RecordNotFound if no Bot is found with the given slug
  def self.from_actor_display_name(slug)
    find_by_slug(slug)
  end

  # Public: finds a Bot with the given slug.
  #
  # slug - The String slug.
  #
  # Returns a Bot
  # Raises ActiveRecord::RecordNotFound if no Bot is found with the given slug
  def self.find_by_slug(slug)  # rubocop:disable GitHub/FindByDef
    with_slugs(slug).first
  end

  # Public: Find the Bot by <slug>[bot>. Previously this could rely on the value
  # stored in the users.login column but now that we generate logins randomly we
  # find by the Integration slug instead.
  #
  # login - a String containing the Integration slug, with or without the LOGIN_SUFFIX
  #
  # Returns a Bot or nil.
  def self.find_by_login(login) # rubocop:disable GitHub/FindByDef
    with_slugs(login).first
  end

  # Public: Find the Bots associated with a list of logins.
  #
  # logins - a list of Strings containing the Integration slugs, with or without the LOGIN_SUFFIX
  #
  # Returns an ActiveRecord::Relation of Bots.
  def self.with_slugs(*slugs)
    if FeatureFlag.vexi.enabled?(:owner_scoped_github_apps, default: false)
      where(id: ids_for_slugs(slugs))
    else
      logins = slugs.flatten.map do |slug|
        slug.ends_with?(LOGIN_SUFFIX) ? slug : "#{slug}#{LOGIN_SUFFIX}"
      end
      where(login: logins)
    end
  end

  # Public: Find the ids for bot records for the associated App slugs
  def self.ids_for_slugs(slugs)
    Integration.where(slug: slugs.flatten.map { |slug| slug.chomp(LOGIN_SUFFIX) }).pluck(:bot_id)
  end

  # Public: Find the Bot associated with the given auto-generated email.
  # Bots do not have an email, however the auto-generated email used for commits
  # may contain a Bot login.
  #
  # email - a String containing the email address to test
  #
  # Returns a Bot or nil.
  def self.find_by_email(email)  # rubocop:disable GitHub/FindByDef
    return if email.blank?
    return unless email.split("@").first.end_with? Bot::LOGIN_SUFFIX

    if matches = email.match(StealthEmail::STEALTH_EMAIL_REGEX)
      where(id: matches[1]).first
    elsif matches = email.match(StealthEmail::OLD_STEALTH_EMAIL_REGEX)
      find_by_login(matches[1])
    end
  end

  # Public: Find the Bots associated with a list of emails.
  # Bots do not have an email, however the auto-generated email used for commits
  # may contain a Bot login.
  #
  # emails - an array of Strings containing the email addresses to test
  #
  # Returns a hash mapping emails to Bot objects.
  def self.find_by_emails(emails) # rubocop:disable GitHub/FindByDef
    emails = Array(emails)
    return {} if emails.empty?

    ids = []
    logins = []
    emails.each do |email|
      next unless email.split("@").first.end_with? Bot::LOGIN_SUFFIX

      if matches = email.match(StealthEmail::STEALTH_EMAIL_REGEX)
        ids.push matches[1].to_i
      elsif matches = email.match(StealthEmail::OLD_STEALTH_EMAIL_REGEX)
        logins.push matches[1].chomp(LOGIN_SUFFIX)
      end
    end

    bots_by_id = Bot.where(id: ids).includes(:integration).index_by(&:id)
    bots_by_login = with_slugs(logins).index_by(&:display_login)

    emails.map do |email|
      if matches = email.match(StealthEmail::STEALTH_EMAIL_REGEX)
        [email, bots_by_id[matches[1].to_i]]
      elsif matches = email.match(StealthEmail::OLD_STEALTH_EMAIL_REGEX)
        [email, bots_by_login[matches[1]]]
      else
        [nil, nil]
      end
    end.to_h.compact
  end

  # For Proxima synced apps, the primary_avatar_url is integration.canonical_avatar_url.
  # For these apps the primary_avatar_url is out of sync with the primary_avatar_path.
  # Since the primary_avatar_url is from Dotcom, the relative Proxima path would be meaningless.
  def async_primary_avatar_path
    async_integration.then do |integration|
      if integration.present?
        # Load the owner association explicitly to fix Graphql Platform::Errors::AssociationRefused
        integration.async_owner.then do
          integration.async_primary_avatar.then do
            integration.primary_avatar_path
          end
        end
      else
        Integration.new.primary_avatar_path
      end
    end
  end

  # Make the primary avatar path the same as its integration.
  memoize def primary_avatar_path
    ActiveRecord::Base.connected_to(role: :reading) do
      async_primary_avatar_path.sync
    end
  end

  def primary_avatar_url(size = nil)
    if integration&.feature_flag_enabled?(:proxima_synced_avatar_url, default: false)
      canonical_avatar_url = T.must(integration).canonical_avatar_url
      return canonical_avatar_url if canonical_avatar_url
    end

    super
  end

  # Public: convenience method to load the relevant installation for a given
  # resource.
  #
  # resource - Resource for integration installation lookup. Supported types: `Repository`
  #
  # Returns nothing.
  def async_load_granular_actor_for(resource)
    async_load_installation_for(resource)
  end

  # Internal: Loads integration installation for the given resource and assigns it to `#installation`.
  # Callers should use async_load_granular_actor_for instead of this method, which
  # ensures PATv2 actors are supported.
  #
  # resource                  - Resource for integration installation lookup.
  #                             Supported types: `Repository`
  # allow_global_installation - Boolean. Whether a global app should use an
  #                             ephemeral GlobalIntegrationInstallation for a
  #                             repository resource.
  #
  # Returns nothing.
  def async_load_installation_for(resource, allow_global_installation: false)
    async_integration.then do |integration|
      next unless integration

      integration.async_installation_for(resource).then do |installation|
        if should_fallback_to_global_installation?(allow_global_installation, resource)
          self.installation = GlobalIntegrationInstallation.for_repository(integration, resource) || installation
        else
          self.installation = installation
        end
      end
    end
  end

  # Returns the AgenticApp instance for this bot, if any.
  # Returns nil if this bot is not associated with an agent.
  def async_agentic_app
    Promise.resolve(AgenticApp.agent_for_bot_id(id))
  end

  private

  # Returns the custom display_login property from the bot's integration, if any.
  # Memoized per-instance (only non-nil results cached to avoid stale nil when
  # the integration association is established after initial object creation).
  def custom_display_login
    return @_custom_display_login if defined?(@_custom_display_login)
    return nil unless self.persisted?

    # `display_login` is purely cosmetic/audit-context and is invoked on every
    # request that resolves a Bot actor (via `User#event_context`), so we route
    # the `bot.integration` lookup to the replica to avoid hammering the primary.
    # Mirrors the pattern used by `primary_avatar_path` above. Safe because no
    # caller writes an integration and then immediately reads its display_login.
    loaded_custom_display_login = ActiveRecord::Base.connected_to(role: :reading) do
      self.async_integration.then do |integration|
        Apps::Privileged.property(:display_login, app: integration)
      end.sync
    end

    @_custom_display_login = loaded_custom_display_login if loaded_custom_display_login
    loaded_custom_display_login
  end

  def owner_scoped_display_login
    return nil unless FeatureFlag.vexi.enabled?(:owner_scoped_github_apps, default: false)

    "#{slug}#{LOGIN_SUFFIX}"
  end

  def async_marketplace_listing_or_app_path
    url_helpers = UrlHelpers

    if GitHub.enterprise?
      Promise.resolve("/#{to_param}")
    else
      async_marketplace_listing.then do |listing|
        if listing&.publicly_listed?
          url_helpers.marketplace_listing_path(listing.slug)
        else
          "/#{to_param}"
        end
      end
    end
  end

  def set_business_id
    return unless GitHub.multi_tenant_enterprise?
    return unless owner = integration&.owner.presence

    business_id =
      case owner
      when Business
        owner.id
      else
        owner.business_id
      end

    self.business_id = business_id
  end

  def should_fallback_to_global_installation?(allow_global_installation, resource)
    !!allow_global_installation && resource.is_a?(Repository)
  end
end
