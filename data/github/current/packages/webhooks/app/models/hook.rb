# typed: true
# frozen_string_literal: true

class Hook < ApplicationRecord::Domain::Hooks
  Hook::Event.eager_load_events!
  extend T::Helpers

  before_destroy :generate_webhook_payload, unless: :new_record?
  after_commit :queue_webhook_delivery, on: :destroy, unless: :new_record?

  include Webhooks::IHook
  include GitHub::Validations
  include Hook::Instrumented
  include Hook::ConfigAccessor
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include Rest::HasPinnedApiVersion
  include ActiveModel::Dirty

  VALID_CONFIG_ATTRIBUTE_NAMES = Set.new(%W[content_type url secret insecure_ssl address])
  WildcardEvent = "*".freeze
  VALID_NAMES = %w[email web cli].freeze
  VALID_INSTALLATION_TYPES = %w(Repository User Business Integration Marketplace::Listing SponsorsListing).freeze
  DISALLOWED_HOSTS_PATTERNS = [
    Regexp.new("\\A(.*\\.)?github\\.net\.?\\z", Regexp::IGNORECASE),
    Regexp.new("\\A(.*\\.)?consul\.?\\z", Regexp::IGNORECASE),
  ].freeze
  LOOPBACK_HOSTS_PATTERN = [
    Regexp.new("\\A(.*\\.)?localhost\.?\\z", Regexp::IGNORECASE),
    Regexp.new("\\A(127|0)\.(?=.*[^\.]$)((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.?){3}\\z", Regexp::IGNORECASE), # match all ip addresses in the 0.0.0.0/8 and 127.0.0.1/8 range
  ].freeze
  INSECURE_SSL_DEFAULT_VALUE = "0".freeze

  belongs_to :installation_target, polymorphic: true
  belongs_to :creator, class_name: "User"
  belongs_to :oauth_application
  has_many :event_types,
    class_name: "HookEventSubscription",
    as: :subscriber,
    dependent: :destroy,
    autosave: true,
    extend: HookEventSubscription::AssociationExtension
  has_many :config_attribute_records,
    class_name: "HookConfigAttribute",
    dependent: :destroy,
    autosave: true,
    extend: HookConfigAttribute::AssociationExtension

  scope :ordered, -> { order(name: :asc, id: :asc) }
  scope :active, -> { where(active: true) }
  # Watch out for this. When 'user' isn't an oauth application, this scope includes all non-oauth hooks whether 'user' can edit them or not.
  scope :editable_by, lambda { |user|
    raise ArgumentError.new("Expected user but none was given.") if user.nil?
    if user.try(:oauth_application)
      where(oauth_application_id: user.oauth_application)
    else
      where("hooks.oauth_application_id IS NULL AND hooks.creator_id IS NOT NULL")
    end
  }

  scope :all_hooks_for_target, lambda { |target|
    where(installation_target: target)
  }

  scope :email_hooks_for_target, lambda { |target|
    where(name: "email", installation_target: target)
  }

  scope :hooks_for_target, lambda { |target|
    where(name: %w[web cli], installation_target: target)
  }

  scope :webhooks_for_target, lambda { |target|
    where(name: "web", installation_target: target)
  }

  @testing_hook_limit = nil

  validates_presence_of :installation_target, unless: :hook_is_being_disabled?
  validates :installation_target_type, inclusion: VALID_INSTALLATION_TYPES, unless: :hook_is_being_disabled?
  validates_presence_of :name, unless: :hook_is_being_disabled?
  validates :name, unicode3: true, unless: :hook_is_being_disabled?
  validate :name_is_valid, unless: :hook_is_being_disabled?
  validate :hook_within_limit, unless: :hook_is_being_disabled?
  validate :hook_is_unique, unless: :hook_is_being_disabled?
  validate :email_hooks_only_on_repos, unless: :hook_is_being_disabled?
  validate :webhook_url_is_valid, unless: :hook_is_being_disabled?
  validate :only_subscribes_to_allowed_events, unless: :hook_is_being_disabled?
  validate :email_address_is_valid, unless: :hook_is_being_disabled?
  validate :when_disabling_and_changing_values, unless: :hook_is_being_disabled?
  validate :hook_config_is_valid

  before_validation :strip_invalid_existing_config_attributes, on: :update
  before_validation :check_events
  before_save :valid_event_names

  # Public: Attributes that can be preloaded from Hookshot if requests by view
  attr_accessor :last_status, :last_status_message

  config_accessor :url, :secret
  config_writer :content_type, :insecure_ssl

  destroy_in_background_with :installation_target, polymorphic_class_name: "Repository"

  # Used to find hooks that are subscribed to a special integrator event.
  # Integrator events are not inherited by an integration's versions nor its
  # installations. These events are triggered only for the integration itself.
  def self.subscribed_to_integrator_event(event_name, installation_target_ids: [])
    return none unless Integration::Events::INTEGRATOR_EVENTS.include?(event_name)

    options = {
      installation_target_type: "Integration",
      hook_event_subscriptions: { name: event_name },
      active: true,
    }

    if installation_target_ids.any?
      options[:installation_target_id] = installation_target_ids
    end

    ids = Hook.joins(:event_types).where(options).distinct.pluck("hooks.id")
    where(id: ids)
  end

  VALUE_CLASS = ActiveModel::Type::Value

  attribute :events, VALUE_CLASS.new
  before_destroy :events # force load before the object is frozen

  # Public: Event names as subscribed via HookEventSubscription.
  #
  # Returns an Array.
  def events
    _read_attribute("events") || T.unsafe(self).event_types.names.tap do |v|
      set_initial_attribute_value("events", v)
    end
  end
  alias_method :subscribed_events, :events

  # Public
  def events=(event_names)
    if events != event_names
      attribute_will_change!("events")
      T.unsafe(self).event_types.names = event_names
      write_attribute("events", T.unsafe(self).event_types.names)
    end
  end

  def valid_event_names
    return true unless webhook?

    events = Hook::EventRegistry.event_classes.map(&:event_type)
    event_names = event_types.map(&:name)

    invalid_event_names = event_names - [Hook::WildcardEvent, *events]
    unless invalid_event_names.empty?
      if invalid_event_names.one?
        errors.add(:base, "#{invalid_event_names.first} is not a valid event name")
      else
        errors.add(:base, "#{invalid_event_names.to_sentence} are not valid event names")
      end

      throw :abort
    end
  end

  # Public: List of event types that a hook of this type is allowed to subscribe to.
  #
  # Returns an Array of event types Strings.
  def allowed_event_types
    @allowed_types ||= begin
                         supported = Hook::EventRegistry.for_target(installation_target)
                         supported.map(&:event_type) + [Hook::WildcardEvent]
                       end
  end

  # Public
  def add_events(event_names)
    self.events += Array(event_names)
  end

  def remove_events(event_names)
    self.events -= Array(event_names)
  end

  def remove_disallowed_events
    disallowed_events = events - allowed_event_types
    remove_events(disallowed_events)
  end

  def editable_by?(user)
    owner = case installation_target
    when Repository, Marketplace::Listing, Integration, SponsorsListing
      installation_target.owner
    when User, Organization, Business
      installation_target
    else
      raise "Unknown hook installation target"
    end

    return false if integration_hook?
    return false if org_hook? && webhook? && created_by_oauth_application?
    return installation_target.async_can_manage_webhooks?(user).sync if repo_hook?
    return installation_target.async_can_write_org_webhooks?(user).sync if org_hook?
    installation_target.adminable_by?(user)
  end

  attribute :config_attributes, VALUE_CLASS.new
  before_destroy :config_attributes # force load before object is frozen

  # Public: Returns config_attribute currently assigned to the hook.
  #
  # Example
  #   config
  #   # => {"key" => "some_key", "value" => "some_value"}
  #
  # Returns a Hash
  def config_attributes
    _read_attribute("config_attributes") || T.unsafe(self).config_attribute_records.config_map.tap do |v|
      set_initial_attribute_value("config_attributes", v)
    end
  end
  alias_method :config, :config_attributes

  # Public: Sets the hooks's config.
  #
  # assigned_configs - A Hash of the config to assign to the Hook.
  #
  # Returns the assigned config Hash.
  def set_config_attributes(assigned_configs, destructive: true)
    unless config_attributes == assigned_configs
      attribute_will_change!("config_attributes")
      T.unsafe(self).config_attribute_records.set_config(assigned_configs, destructive: destructive)
      write_attribute("config_attributes", T.unsafe(self).config_attribute_records.config_map)
    end
  end

  def config_attributes=(new_config)
    unless new_config.nil?
      unless new_config.key? "insecure_ssl"
        new_config["insecure_ssl"] = INSECURE_SSL_DEFAULT_VALUE
      end
    end
    set_config_attributes(new_config)
  end
  alias_method :config=, :config_attributes=

  def set_initial_attribute_value(attr, value)
    target = @attributes
    target[attr] = ActiveModel::Attribute.from_database(attr, value, VALUE_CLASS.new)
  end
  private :set_initial_attribute_value

  # Public: Performs a partial update on the existing config. Existing values will
  # be updated and new values will be added. If partial_config contains nil or
  # blank values for keys that already exist, those records will be deleted.
  def update_existing_config(partial_config)
    set_config_attributes(config_attributes.merge(partial_config))
  end

  # Public: Performs a partial update on the existing config. Existing values will
  # be updated and new values will be added.
  def partial_config=(partial_config)
    set_config_attributes(config_attributes.merge(partial_config), destructive: false)
  end

  # Public: return non-sensitive config values for viewing config
  # This masks the `secret` attribute.
  #
  # config_to_mask - Optional hash of config to mask
  #
  # Return a modified version of the config
  def masked_config(config_to_mask = config)
    return {} unless config_to_mask

    masked_config = config_to_mask.dup
    if masked_config["secret"].present?
      masked_config["secret"] = "********"
    end

    if masked_config["url"].present?
      masked_config["url"] = with_tenant_scoped_url(masked_config["url"])
    end

    masked_config.merge!("insecure_ssl" => insecure_ssl, "content_type" => content_type)

    # Don't show any previously existing invalid config keys.
    masked_config.filter { |k, _| VALID_CONFIG_ATTRIBUTE_NAMES.include?(k) }
  end

  # Public: Toggles the active status of a webhook, sets the reason for disabling,
  # and sends an email to hook admins.
  #
  # The order of operations is important here - we must set the reason before calling
  # toggle to ensure the reason field is populated for the instrument_active_changed
  # callback to use.
  #
  # Returns a boolean indicating whether the toggled record was successfully saved.
  def toggle_active_status_from_stafftools(disable_reason:)
    self.stafftools_disable_reason = disable_reason
    self.toggle!(:active)
    if self.active?
      HookMailer.stafftools_enable_notice(self).deliver_later
      HookMailer.oauth_hook_stafftools_enable_notice(self).deliver_later if self.created_by_oauth_application?
    else
      HookMailer.stafftools_disable_notice(self).deliver_later
      HookMailer.oauth_hook_stafftools_disable_notice(self).deliver_later if self.created_by_oauth_application?
    end
  end

  def owner_name_and_type
    case installation_target
    when Repository
      "#{installation_target.nwo} repository"
    when Organization
      "#{installation_target.login} organization"
    when Business
      "#{installation_target.name} enterprise"
    when Integration
      "#{installation_target.name} app"
    when SponsorsListing
      "#{installation_target.owner&.login} sponsors listing"
    when Marketplace::Listing
      "#{installation_target.slug} marketplace listing"
    end
  end

  def insecure_ssl
    config["insecure_ssl"] || "0"
  end

  def content_type
    config["content_type"] || "form"
  end

  def name=(value)
    short = value.to_s.dup
    short.gsub!(/[\s\-]/, "")
    short.downcase!
    write_attribute :name, short
  end

  def display_name
    if cli_hook?
      "GitHub Command Line - #{creator&.name}"
    elsif name == "email"
      "Email"
    else
      "webhook"
    end
  end

  def last_status_to_label
    Hookshot::Delivery.status_code_to_label(last_status)
  end

  # Public: The canonical name used by hookshot to identify the parent.
  #
  # Returns a String
  def hookshot_parent_id
    "#{installation_target.class.name.downcase}-#{installation_target_id}"
  end

  # Determines if this hook can respond to the given event.
  #
  # event_type - The event type as a String or Symbol (e.g. :push)
  #
  # Returns true if the hook can respond, or false.
  def call?(event_type, is_testing: false, action: nil)
    (is_testing || active?) && fires_for_event?(event_type, action: action)
  end

  def enable(data = nil)
    configure_with(true, data)
  end

  def disable(data = nil)
    configure_with(false, data)
  end

  def configure_with(active, data = nil)
    self.active = active
    self.config = data.to_hash if data
    save
  end

  # Public: Queues an event to ping the hook.
  #
  # Returns nothing.
  def ping
    instrument :ping
  end

  def generate_webhook_payload
    event = Hook::Event::MetaEvent.new(
      hook_id: self.id,
      actor_id: (GitHub.context[:actor_id] || User.ghost),
      action: :deleted,
      triggered_at: Time.now,
    )
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  def queue_webhook_delivery
    unless defined?(@delivery_system)
      raise "'generate_webhook_payload' must be called before 'queue_webhook_delivery'"
    end

    @delivery_system&.deliver_later
  end

  # Public: Logs hook exception to failbot.
  #
  # exception  - The Exception that was raised.
  # event      - String name of the event that was triggered.
  # event_path - The relative String HTTP path to the services app.
  # faraday    - The Faraday::Connection instance that attempted the Hook call.
  # failbot    - Optional Failbot instance to use.  Default: Failbot.
  #
  # Returns nothing.
  def log_to_failbot(exception, event, event_path, faraday, failbot = nil)
    return if exception.is_a?(Faraday::TimeoutError) # XXX too much noise
    failbot ||= Failbot
    failbot.report exception,
      event_type: event,
      event_service_name: name,
      hook_call_url: faraday.build_url(event_path).to_s,
      hook_id: id
  end

  def similar_to?(other_hook)
    same_attributes?(other_hook, :installation_target_type, :installation_target_id, :name, :config) && overlapping_events?(other_hook)
  end

  # Ensures the given event is valid.
  #
  # event_type - String or Symbol event name (e.g. :push).
  #
  # Returns true if the event exists, or false.
  def self.valid_event_type?(event_type)
    return false unless event_type.present?

    !![WildcardEvent, *Hook::EventRegistry.event_types].include?(event_type.to_s)
  end

  # Public: Prepares events and toggles the hook's active state
  # based on existing hooks.
  #
  # Returns true.
  def check_events
    normalize_events

    # Only disable an eventless Webhook if it belongs to a GitHub App.
    #
    # We send events that are not listed as options for the
    # integrator. Like when an installation is created,
    # or when repositories have been added or removed
    # from an IntegrationInstallation.
    if !integration_hook? && events.blank?
      self.active = false
    end

    true
  end

  # Private: Normalizes events, removes duplicates, and keeps
  # events in a correct state.
  #
  # Returns Array of events.
  def normalize_events
    normalized_events = events.dup.delete_if { |e| !self.class.valid_event_type?(e) }
    normalized_events = [WildcardEvent] if normalized_events.include?(WildcardEvent)
    normalized_events.uniq!
    self.events = normalized_events
  end

  def revalidate_hook_limit?
    if !active?
      false
    elsif new_record? || active_changed?
      true
    else
      events_changed?
    end
  end

  def hook_within_limit
    return unless revalidate_hook_limit?
    counts = hook_counts_per_event
    events.each do |e|
      next if counts[e].to_i < hook_limit
      GitHub.dogstats.increment("hooks.limited")
      errors.add(:base, "The #{e.inspect} event cannot have more than #{hook_limit} hooks")
    end
  end

  def hook_limit
    return @testing_hook_limit if @testing_hook_limit

    limit = if repo_hook?
      Webhooks.domain.hook_limit(self)
    else
      installation_target.try(:hook_limit)
    end

    limit || GitHub.hook_limit
  end

  def hook_limit=(limit)
    raise "#hook_limit= should only be called in test env" unless GitHub.can_override_hook_limit?
    @testing_hook_limit = limit
  end

  def hook_counts_per_event
    counts = {}
    return counts unless installation_target

    sibling_hooks.each do |hook|
      (events & hook.events).each do |event|
        counts[event] = counts[event].to_i + 1
      end
    end
    counts
  end

  def possible_similar_hooks
    sibling_hooks.select { |hook| hook.name == name }
  end

  def sibling_hooks
    @sibling_hooks ||= sibling_hooks!
  end

  def sibling_hooks!
    return [] unless installation_target

    cond = []
    cond = new_record? ? [] : ["id <> ?", id]

    if repo_hook?
      Hook.hooks_for_target(installation_target).where(cond)
    else
      return [] unless installation_target.respond_to?(:hooks)
      installation_target.hooks.where(cond)
    end
  end

  def hook_conditions(*cond)
    if !new_record?
      cond[0] << " and id <> ?"
      cond << id
    end
    cond
  end

  def repo_hook?
    installation_target.is_a?(Repository)
  end

  def org_hook?
    installation_target.is_a?(Organization)
  end

  def business_hook?
    installation_target.is_a?(Business)
  end

  def integration_hook?
    installation_target.is_a?(Integration)
  end

  def marketplace_listing_hook?
    installation_target.is_a?(Marketplace::Listing)
  end

  def sponsors_listing_hook?
    installation_target.is_a?(SponsorsListing)
  end

  def hook_type
    case installation_target
    when Organization
      :org
    when Repository
      :repo
    when Marketplace::Listing
      :marketplace_listing
    else
      installation_target.class.name.demodulize.underscore.to_sym
    end
  end

  def webhook?
    name == "web"
  end

  def cli_hook?
    name == "cli"
  end

  def same_attributes?(other_hook, *attrs)
    attrs.all? { |attr| send(attr) == other_hook.send(attr) }
  end

  def overlapping_events?(other_hook)
    (events & other_hook.events).any?
  end

  def track_creator(creator)
    self.creator = creator
    self.oauth_application_id = creator.oauth_access.application_id if creator.using_oauth_application?
  end

  def creator_name
    if created_by_oauth_application?
      "#{T.must(oauth_application).name} on behalf of #{T.unsafe(self).creator.display_login}"
    elsif created_by_user?
      T.must(creator).display_login
    else
      "unknown"
    end
  end

  def created_by_oauth_application?
    creator && oauth_application
  end

  def created_by_user?
    creator && !oauth_application
  end

  def created_by_unknown?
    !creator && !oauth_application
  end

  # Internal: Check if this Hook subscribes to the given event.
  #
  # event - A String or Symbol event name
  #
  # Returns Boolean.
  def fires_for_event?(event, action: nil)
    return false unless allowed_event_types.include?(event.to_s)
    event_class = Hook::EventRegistry.for_event_type(event)

    if from_wildcard?
      # If the Hook is subscribed to the wildcard, do not send feature flagged
      # events. Feature flagged events must be subscribed to specifically without
      # using the wildcard.
      if event_class.flagged_actions.present?
        event_class.flagged_actions.map(&:to_sym).exclude?(action.to_sym)
      else
        !event_class.feature_flagged?
      end
    else
      event_class.auto_subscribed? || event_types.exists?(name: event)
    end
  end

  # Public: Determines if the reason this event is firing is because
  # it's from a wildcard, rather than a named event.
  #
  # Returns a Boolean.
  def from_wildcard?
    !!event_types.where(name: WildcardEvent).first
  end

  # Internal: Returns whether or not we're running in a testing environment that
  # actually cares about the webhook being delivered.
  #
  # Returns a Boolean.
  def self.delivers_in_test?
    false
  end

  # Public: Sets a random secret (used by managed integrations)
  #
  # Returns a String
  def generate_secret
    T.unsafe(self).secret = SecureRandom.hex(20)
  end

  class ParentAsActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
      new(id)
    end

    def initialize(index_key)
      @index_key = index_key
    end

    def flipper_id
      "#{self.class.name}:#{@index_key.gsub(":", "_")}"
    end

    def vexi_id
      flipper_id
    end
  end

  class EventAsActor
    include GitHub::FlipperActor
    include GitHub::VexiActor

    def self.find_by_id(event) # rubocop:disable GitHub/FindByDef
      new(event.to_s)
    end

    def initialize(index_key)
      @index_key = index_key
    end

    def flipper_id
      "#{self.class.name}:#{@index_key.gsub(":", "_")}"
    end

    def vexi_id
      flipper_id
    end
  end

  def parent_actor
    @parent_actor ||= ParentAsActor.new(hookshot_parent_id)
  end

  def on_denylist?
    return false unless integration_hook?
    # This feature should only be "enabled" to deny specific integrations -- never enabled by itself. If someone does inadvertently enable it, then ignore it and don't deny anything.
    return false if GitHub.flipper[:webhooks_denylist].enabled?
    GitHub.flipper[:webhooks_denylist].enabled?(installation_target)
  end

  # Public: The value of the `url` config attribute. If the hook is an integration hook, the integration  is
  # syncable to Proxima and has a templated URL, we will interpolate the hostname into the URL
  # (e.g., `https://{hosname}/callback` -> `https://staffship01-ghe.com/callback`).
  #
  # Returns: String
  def url
    with_tenant_scoped_url(raw_url)
  end

  # Public: The value of the `url` config attribute.
  #
  # Returns: String
  def raw_url
    config["url"]
  end

  # Public: The hook's config with the `url` attribute interpolated with the tenant scoped URL.
  #
  # Returns: Hash
  def config_with_tenant_scoped_url
    return config if config["url"].blank?

    conf = config.deep_dup
    conf["url"] = with_tenant_scoped_url(conf["url"])
    conf
  end

  def with_tenant_scoped_url(value)
    return value unless integration_hook?
    return value unless ::ProximaAppRequest::TenantScopedUrl.should_generate?(app: installation_target, url: value)

    ::ProximaAppRequest::TenantScopedUrl.generate(value, installation_target)
  end

  private

  # Private: Used to temporarily hold the reason so it can be used by instrument_active_changed callback
  attr_accessor :stafftools_disable_reason

  def hook_is_being_disabled?
    # do we have changes and are we disabling
    return false unless changes["active"] == [true, false]
    remaining = changes.keys - ["active"]
    remaining.all? { |key| changes[key][0] == changes[key][1] }
  end

  def when_disabling_and_changing_values
    # check if there are changes and active is toggled and they are more than 1 and errors
    if changes && changes.length > 1 && changes[:active] == [true, false] && errors.any?
      errors.add(:base, "To mark this hook as inactive only send the active field or fix the invalid fields")
    end
  end

  def name_is_valid
    valid = VALID_NAMES.include?(name)
    errors.add(:base, "Name can only be set to 'web' or 'email'.") unless valid
    valid
  end

  def hook_is_unique
    if active_webhooks_with_overlapping_events?
      GitHub.dogstats.increment("hooks.duped")
      errors.add(:base, "Hook already exists on this #{repo_hook? ? "repository" : "organization"}")
    end
  end

  def active_webhooks_with_overlapping_events?
    possible_similar_hooks.any? do |hook|
      similar_to?(hook)
    end
  end

  def webhook_url_is_valid
    return unless webhook?

    if raw_url.blank?
      errors.add(:url, "cannot be blank")
      return
    end

    # Webhooks must have a URL configured for delivery, and we've experienced
    # various delivery errors when URLs include whitespace (especially leading).
    # This ensures we strip the whitespace out.
    stripped_url = raw_url.strip
    update_existing_config({ "url" => stripped_url })

    limit = T.unsafe(self).config_attribute_records.columns_hash["value"].limit

    if url.length > limit
      errors.add(:url, "must have no more than #{limit} characters")
      return
    end

    begin
      uri = URI(url)
    rescue URI::InvalidURIError
      errors.add(:url, "is not valid. Please make sure that you encode all special characters first")
      return
    end

    if uri.scheme.nil?
      errors.add(:url, "is missing a scheme")
      return
    end

    unless uri.scheme =~ /https?/
      errors.add(:url, "scheme is invalid")
      return
    end

    if marketplace_listing_hook? || sponsors_listing_hook?
      unless uri.scheme =~ /https/
        errors.add(:url, "must be secure")
      end
      if config["insecure_ssl"] && config["insecure_ssl"] != "0"
        errors.add(:base, "SSL must be verified")
      end
      return
    end

    unless UrlHelper.valid_host?(uri.host)
      errors.add(:url, "host is invalid")
      return
    end

    # NOTE: This validation check is just for UX reasons and does not securely
    # enforce restrictions to these IP addresses
    if disallow_loopback?(uri)
      errors.add(:url, "is not supported because it isn't reachable over the public Internet (#{uri.host})")
    end

    if !GitHub.enterprise? &&
        DISALLOWED_HOSTS_PATTERNS.any? { |pattern| !!pattern.match(uri.host) }
      errors.add(:url, "host is not allowed")
      return
    end

    uri
  end

  def disallow_loopback?(uri)
    return false if GitHub.enterprise? && integration_hook? && installation_target.can_set_loopback_webhook?
    true if !GitHub.allow_webhook_loopback_addresses? && LOOPBACK_HOSTS_PATTERN.any? { |pattern| !!pattern.match(uri.host) }
  end

  def only_subscribes_to_allowed_events
    invalid_events = (events - allowed_event_types)
    unless invalid_events.empty?
      errors.add(:base, "These events are not allowed for this hook: #{invalid_events.join ", "}")
    end
  end

  def email_hooks_only_on_repos
    return unless name == "email"
    return if repo_hook?

    errors.add(:base, "Email hooks are only supported on repositories.")
  end

  def email_address_is_valid
    return unless name == "email"

    if config["address"].blank?
      errors.add(:base, message: "Address is required", config_attribute: :address)
      return
    end

    address_value = config["address"].strip
    emails = address_value.split(" ").map(&:strip)

    if emails.length > 2
      errors.add(:base, :invalid, message: "You may only add a maximum of two email addresses.", config_attribute: :address)
      return
    end

    unless emails.all? { |email| email.match(User::EMAIL_REGEX) }
      errors.add(:base, :invalid, message: "Address must be up to 2 valid email addresses separated by whitespace.", config_attribute: :address)
      nil
    end
  end

  def strip_invalid_existing_config_attributes
    return unless webhook?
    filtered_config = config_attributes.reject do |key|
      # Strip out config attributes that don't match the allow list, but only if they already existed in the config.
      # For new attributes that are being set, do not strip them so the validation will fail.
      !VALID_CONFIG_ATTRIBUTE_NAMES.include?(key) && should_strip_config_key?(key)
    end
    set_config_attributes(filtered_config)
  end

  def should_strip_config_key?(key)
    # If we don't have changes, default to stripping the config key for safety.
    # We should likely always have changes since this only runs before validation on an update.
    return true unless changes["config_attributes"] && changes["config_attributes"].first
    # If we have changes, only strip if the key already existed before the change, otherwise leave so that
    # validation will fail.
    changes["config_attributes"].first.key?(key)
  end

  def hook_config_is_valid
    return unless webhook?

    config_attributes.each do |key, _|
      next if VALID_CONFIG_ATTRIBUTE_NAMES.include?(key)
      errors.add(:base, "Invalid config attribute: #{key}")
    end
  end
end
