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

  has_one :marketplace_listing, through: :integration

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
    if GitHub.flipper[:owner_scoped_github_apps].enabled?
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
    if GitHub.flipper[:owner_scoped_github_apps].enabled?
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
    if GitHub.flipper[:owner_scoped_github_apps].enabled?
      @display_login = nil # Bust memoization
    else
      self[:login] = "#{slug}#{LOGIN_SUFFIX}"
    end
  end

  def display_login
    if GitHub.flipper[:owner_scoped_github_apps].enabled?
      @display_login ||= "#{slug}#{LOGIN_SUFFIX}"
    else
      login
    end
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
    safe_slug = slug || async_integration.sync&.slug || login

    @to_param = UrlHelpers.alias_app_path(safe_slug)[1..-1]
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

  def ability_delegate
    installation
  end

  def to_query_filter
    self.class.query_filter_from_login(slug)
  end

  # Internal: converts a bot's login or slug to a string that's usable in a
  # search filter (e.g. author:app/hubot)
  def self.query_filter_from_login(login_or_slug)
    "app/#{login_or_slug.chomp(LOGIN_SUFFIX)}"
  end

  # Public: Find the Bot associated with the given token. The returned Bot has
  # its installation context set to the installation associated with the given
  # token. The installation context determines the Bot's permissions (i.e.,
  # which actions it can take on which Repositories).
  #
  # value - The String token value.
  #
  # Returns a Bot or nil.
  def self.find_by_token(value, push_token_to_audit_log: false) # rubocop:disable GitHub/FindByDef
    return if value.blank?

    hashed_value = AuthenticationToken.hash_token(value)

    token =
      if push_token_to_audit_log
        token_record = AuthenticationToken.with_unhashed_token(value).first

        # This Audit context addition catches integration token uses which are different from logged_in sessions
        Audit.context.push(token_id: token_record&.id)

        # Validate these on the object, so that even if  the token is invalid
        # we can add it to the audit log context.
        if token_record && token_record.expired?
          nil
        elsif token_record && !token_record.authenticatable_type.in?(AUTHENTICATABLE_TYPES)
          nil
        else
          token_record
        end
      else
        AuthenticationToken
          .includes(:authenticatable)
          .where(authenticatable_type: AUTHENTICATABLE_TYPES)
          .active
          .with_unhashed_token(value)
          .first
      end

    # Double check hashed token because of case sensitivity problem with
    # current column type.
    token = nil unless token && token.hashed_value == hashed_value

    tags = []
    if (authenticatable = token&.authenticatable)
      tags << "result:success"
      tags << "token_type:authenticatable"
      authenticatable = load_parent_installation(authenticatable, tags)
      tags << "missing_bot:true" if authenticatable.bot.nil?
      GitHub.dogstats.increment("bot.find_by_token", tags: tags)

      return authenticatable.bot
    elsif token && (bot = bot_read_from_collab_primary(token, tags))
      tags << "result:success"
      tags << "token_type:bot"
      GitHub.dogstats.increment("bot.find_by_token", tags: tags)

      return bot
    end

    failure_type = token.nil? ? "missing:token" : "missing:authenticatable"
    tags.concat([failure_type, "result:failure"])
    GitHub.dogstats.increment("bot.find_by_token", tags: tags)

    nil
  end

  def self.load_parent_installation(authenticatable, tags)
    return authenticatable unless authenticatable.class.name == "ScopedIntegrationInstallation"
    return authenticatable if authenticatable.parent.present?

    tags << "missing_parent:true"

    # A ScopedIntegrationInstallation's parent should never be nil.
    #
    # If it is, it's due to replication lag. This sets the parent to what it
    # should be so that we can continue the request.
    #
    # See https://github.com/github/github/issues/142265 for further details.
    ActiveRecord::Base.connected_to(role: :writing, prevent_writes: true) do
      authenticatable.parent = IntegrationInstallation.find_by(id: authenticatable.integration_installation_id)
    end

    authenticatable
  end

  def self.bot_read_from_collab_primary(token, tags)
    return false unless token.authenticatable_type == "ScopedIntegrationInstallation"
    tags << "check_primary:true"

    installation = ActiveRecord::Base.connected_to(role: :writing, prevent_writes: true) do
      ScopedIntegrationInstallation.find_by(id: token.authenticatable_id)
    end

    if installation.nil?
      tags << "primary_lookup:failed"
      return
    end

    return installation.bot unless installation.parent.nil?
    load_parent_installation(installation, tags).bot
  end

  # Public: Implements the flipper finder interface for Bots
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
    if GitHub.flipper[:owner_scoped_github_apps].enabled?
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
    if integration&.feature_enabled?(:proxima_synced_avatar_url)
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
  # resource - Resource for integration installation lookup. Supported types: `Repository`
  #
  # Returns nothing.
  def async_load_installation_for(resource)
    async_integration.then do |integration|
      next unless integration

      integration.async_installation_for(resource).then do |installation|
        self.installation = installation
      end
    end
  end

  private

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
end
