# typed: true
# frozen_string_literal: true

require "oauth_util"

# An Audit Log Entry model encapsulating audit log event information.
# Attributes listed in KEYS are initialized via self.new_from_hash(hash).
# Several string attributes, noteably those listed as attr_writer, may be
# subsequently set as an object type instead here or by an external
# consumer view_model such as by results_view.preload_associations().

class AuditLogEntry
  include AuditLogEntry::Actions
  include AuditLogEntry::UserDependency
  include AuditLogEntry::OrganizationDependency
  include AuditLogEntry::EnterpriseDependency

  attr_accessor :action, :actor_id, :actor_ip, :staff_actor, :staff_actor_id,
    :actor_location, :business_id, :commit_comment_id, :data, :from, :note, :oauth_app_id,
    :org_id,  :project_id, :repo, :repo_id, :hook_id, :user_id, :hit, :issue_comment_id, :issue_id,
    :marketplace_listing_id, :discussion_post, :discussion_post_id, :marketplace_listing_plan_id,
    :discussion_post_reply, :discussion_post_reply_id, :minimizable_id, :minimizable_type,
    :session_impersonated, :device_cookie, :public_repo, :hashed_token, :token_id, :token_scopes,
    :token_type, :external_identity_username, :external_identity_nameid, :programmatic_access_type,
    :discussion_id, :discussion_comment_id

  attr_writer :actor, :actor_obj, :business, :user, :user_obj, :created_at,
    :commit_comment, :minimizable, :issue_comment, :org, :org_obj,
    :organization, :project, :marketplace_listing, :marketplace_listing_plan

  KEYS = Set.new([:action, :actor, :actor_id, :actor_ip, :staff_actor, :staff_actor_id,
    :actor_location, :business, :business_id, :commit_comment_id, :commit_comment,
    :created_at, :data, :from, :note, :oauth_app_id, :org,
    :org_id, :project, :project_id, :repo, :repo_id, :hook_id, :user, :user_id,
    :issue_comment_id, :issue_comment, :issue_id, :marketplace_listing_id, :marketplace_listing,
    :marketplace_listing_plan_id, :marketplace_listing_plan, :discussion_post, :discussion_post_id,
    :discussion_post_reply, :minimizable_id, :minimizable_type, :session_impersonated,
    :minimizable, :discussion_post_reply_id, :staff_actor, :staff_actor_id,
    :device_cookie, :public_repo, :hashed_token, :token_id, :token_scopes, :token_type,
    :external_identity_username, :external_identity_nameid, :programmatic_access_type]).freeze

  PUBLIC_REPO_CUTOFF = Time.at(1649203140) # 2022-04-05T23:59:00Z

  def self.keys
    KEYS
  end

  # Converts an audit Hash into an AuditLogEntry
  #
  #   hash - A Hash of log data returned from `GitHub.audit.search`
  #
  # Returns an AuditLogEntry
  def self.new_from_hash(hash)
    entry = new
    if hash.is_a?(Audit::Elastic::Hit)
      entry.hit = hash
    else
      entry.hit = Audit::Elastic::Hit.new("_source" => hash)
    end
    all_key_values = hash[:data] ? hash.merge(hash[:data]) : hash
    all_key_values.each_pair do |key, value|
      key = key.to_sym
      next unless keys.include?(key)
      entry.send(:"#{key}=", value)
    end
    entry
  end

  # Converts an Array of audit Hashes into an Array of AuditLogEntries
  #
  #   logs - An Array of Hashes returned from `GitHub.audit.search`
  #          You can directly pass the return value of `GitHub.audit.search`
  #
  # Returns an Array of AuditLogEntries
  def self.new_from_array(logs)
    Array(logs).map { |log| new_from_hash log }.reject(&:hidden?)
  end

  # Converts an Array of audit Hashes into an Array of AuditLogEntries only
  # returning those that can be viewed by business owners.
  #
  #   logs - An Array of Hashes returned from `GitHub.audit.search`
  #          You can directly pass the return value of `GitHub.audit.search`
  #
  # Returns an Array of AuditLogEntries
  def self.for_businesses(logs)
    new_from_array(logs).reject(&:hidden_from_businesses?)
  end

  # Converts an Array of audit Hashes into an Array of AuditLogEntries only
  # returning those that can be viewed by organizations.
  #
  #   logs - An Array of Hashes returned from `GitHub.audit.search`
  #          You can directly pass the return value of `GitHub.audit.search`
  #
  # Returns an Array of AuditLogEntries
  def self.for_orgs(logs)
    new_from_array(logs).reject(&:hidden_from_orgs?)
  end

  # Converts an Array of audit Hashes into an Array of AuditLogEntries only
  # returning those that can be viewed by users.
  #
  #   logs - An Array of Hashes returned from `GitHub.audit.search`
  #          You can directly pass the return value of `GitHub.audit.search`
  #
  # Returns an Array of AuditLogEntries
  def self.for_users(logs)
    new_from_array(logs).reject(&:hidden_from_users?)
  end

  DENIED_METADATA_KEYS = %w[
    connections
    data
    hit
    timing
  ]

  ALLOWED_METADATA_KEYS = %w[
    action
    active
    active_was
    actor
    blocked_user
    config
    config_was
    content_type
    created_at
    deploy_key_fingerprint
    emoji
    events
    events_were
    explanation
    fingerprint
    hook_id
    limited_availability
    message
    name
    old_user
    openssh_public_key
    org
    previous_visibility
    read_only
    repo
    target_login
    team
    user
    visibility
  ]

  SELF_ALLOWED_METADATA_KEYS = ALLOWED_METADATA_KEYS +
                               %w(message_body email actor_ip actor_location)

  STAFF_ALLOWED_METADATA_KEYS = ALLOWED_METADATA_KEYS +
                                %w(message_body staff_actor staff_actor_id business)

  INTERNAL_IP_ADDRESSES = [
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "::1/128",
    "fe80::/10",
    "fc00::/7",
    "192.30.252.0/22",
  ].map { |cidr| IPAddr.new(cidr) }

  # Public: Determine if an audit log key is included in the denied keys list to not
  # be returned in the metadata.
  #
  # key - The key to check for as String or Symbol.
  #
  # Returns true if denied, false if allowed.
  def self.denied_key?(key)
    DENIED_METADATA_KEYS.include?(key.to_s)
  end

  # Public: Determine if an audit log key is included in the allowed keys list to be
  # returned when the actor is not the user viewing the metadata.
  #
  # key - The key to check for as String or Symbol.
  #
  # Returns true if allowed, false if denied.
  def self.allowed_key?(key)
    ALLOWED_METADATA_KEYS.include?(key.to_s)
  end

  # Public: Determine if an audit log key is included in the allowed keys list to be
  # returned when the actor is the user viewing the metadata.
  #
  # key - The key to check for as String or Symbol.
  #
  # Returns true if allowed, false if not.
  def self.allowed_key_for_self?(key)
    SELF_ALLOWED_METADATA_KEYS.include?(key.to_s)
  end

  # Public: Determine if an audit log key is included in the allowed keys list to be
  # returned when the actor is staff viewing the metadata.
  #
  # key - The key to check for as String or Symbol.
  #
  # Returns true if allowed, false if not.
  def self.allowed_key_for_staff?(key)
    STAFF_ALLOWED_METADATA_KEYS.include?(key.to_s)
  end

  # Convert this AuditLogEntries into a Hash containing its data
  #
  # Returns a Hash
  def to_hash
    KEYS.each_with_object({}) do |var, hash|
      hash[var] = instance_variable_get("@#{var}")
    end
  end

  # Retrieve a Hash of metadata to render or return to the user.
  # We"re basically taking the JSON from elasticsearch and making it presentable
  #
  # Returns a sorted Hash
  def metadata(time_zone: Time.zone)
    if @time_zone && time_zone == @time_zone
      return @metadata
    end

    @time_zone = time_zone
    @metadata = begin
      raw_data = self.to_hash.merge(data || {})
      raw_data[:@timestamp] = timestamp(at_timestamp, time_zone)
      raw_data[:actor_location] = geolocation
      raw_data[:created_at] = created_at_timestamp(time_zone: time_zone)
      raw_data[:_invalid_at] = marked_invalid_at(time_zone: time_zone)

      raw_data.reject! { |key, _value| self.class.denied_key?(key) }
      raw_data.reject! { |_key, value| value.nil? }

      raw_data.symbolize_keys!

      Hash[raw_data.sort_by { |key, _value| key.to_s }]
    end
  end

  def user_metadata
    return metadata if metadata[:action] != "repo.add_member"
    metadata.reject { |key, _value| %w(actor_ip actor_location).include?(key.to_s) }
  end

  # Takes the Hash from `metadata` and filters it down to a list of keys
  # approved for giving to end users
  #
  # current_user - The user the metadata is being sanitized for (default nil)
  #
  # Returns a sorted Hash
  def sanitized_metadata(current_user = nil)
    if current_user&.site_admin?
      metadata.select { |key, _value| self.class.allowed_key_for_staff?(key) }
    elsif show_self_metadata?(current_user)
      metadata.select { |key, _value| self.class.allowed_key_for_self?(key) }
    else
      metadata.select { |key, _value| self.class.allowed_key?(key) }
    end
  end

  # Converts the output of `sanitized_metadata` into pretty JSON
  # Support can send this JSON to users who request large amounts of audit logs
  def pretty_metadata
    JSON.pretty_generate Hash[sanitized_metadata]
  end

  # Public: The hook name for this audit entry.
  #
  # Returns a String.
  def hook_name
    data["name"] if data["hook_id"].present?
  end

  # Find the user for this entry.
  #
  # Returns an instance of User
  def user
    return @user_obj if defined?(@user_obj)

    @user_obj = User.find_by(id: user_id)
  end

  # Fallback on the ghost user when the original actor's been deleted or
  # doesn't exist.
  #
  # See User.ghost for more.
  def safe_user
    user || User.ghost
  end

  # Find the organization for this entry.
  #
  # Returns an instance of User
  def org
    return @org_obj if defined?(@org_obj)

    @org_obj = Organization.find_by(id: org_id)
  end

  # Returns true if an organization is present in the entry,
  # false otherwise.
  #
  # Returns a Boolean.
  def org?
    org.present?
  end

  # Try to get the organization's actual profile name even if
  # the organization has been deleted.
  #
  # Returns a String.
  def safe_organization_name
    if org?
      org.safe_profile_name
    else
      hit[:org]
    end
  end

  # Find the business for this entry.
  #
  # Returns an instance of Business.
  def business
    @business_obj ||= Business.find_by(id: business_id)
  end

  # Returns true if a business is present in the entry, otherwise false.
  #
  # Returns a Boolean.
  def business?
    business.present?
  end

  # Try to get the business name even if it has been deleted.
  #
  # Returns a String.
  def safe_business_name
    if business?
      business.name
    else
      hit[:business]
    end
  end

  # Determine if the session was impersonated
  def impersonated?
    session_impersonated.present?
  end

  # Find the actor for this entry.
  #
  # Returns an instance of User
  def actor
    return @actor_obj if defined?(@actor_obj)

    @actor_obj = User.find_by(id: actor_id)
  end

  def actor?
    actor.present?
  end

  # Public: Determine if there is a known actor for this action.
  #
  # Returns true if actor or login is present, false otherwise.
  def actor_present?
    (actor?).tap do |present|
      if !present
        instrument_missing_actor
      end
    end
  end

  # Public: Check to see if the safe actor login is the same as the ghost
  # user login. Helps to determine if +safe_actor_login+ is indeed a valid
  # actor that has been deleted or just the ghost user.
  #
  # Returns true if ghost actor, false otherwise.
  def actor_missing?
    !actor_present?
  end

  def actor_deleted?
    !actor?
  end

  # Fallback on the ghost user when the original actor's been deleted or
  # doesn't exhist.
  #
  # See User.ghost for more.
  def safe_actor
    actor || User.ghost
  end

  # Try to get the actor's actual login even if the account has been deleted
  # and the actor is a ghost user.
  #
  # Returns a String
  def safe_actor_login
    if hit[:actor].present?
      hit[:actor]
    else
      User.ghost.login
    end
  end

  # Public: Determines if the actor performed the action against themselves.
  #
  # Returns true if same user, false otherwise.
  def own_entry?
    actor_id == user_id
  end

  # Converts Audit's created_at format into a Ruby-friendly one.
  #
  # Returns an instance of Time
  def created_at
    @created_at_time ||= Time.at(@created_at.to_i / 1000.0)
  end

  # Converts Audit's @timestamp format into a Ruby-friendly one.
  #
  # Returns an instance of Time
  def at_timestamp
    @timestamp_time ||= Time.at(@hit[:@timestamp].to_i / 1000.0)
  end

  # Returns a String "Timestamp" version of created_at,
  #   e.g. "2012-03-13 12:47:22"
  def created_at_timestamp(time_zone: Time.zone)
    timestamp(created_at, time_zone)
  end

  def timestamp(time, time_zone = Time.zone)
    time.in_time_zone(time_zone).strftime "%Y-%m-%d %H:%M:%S %z"
  end

  # Converts the log's IP into a nice location string, helpful for identifying
  # suspect activity like attempted logins from the other side of the earthsphere
  #
  # Returns a String
  def geolocation
    return unless location
    location.values_at(:city, :region_name, :country_name).compact.join(", ")
  end

  # Public: Actor's location including country,
  #
  # TODO: Build true AuditLogEntry::Location to handle
  #
  # Returns a Hash with location details
  def location
    @location ||= if actor_location?
      actor_location.with_indifferent_access
    elsif external_ip?
      GitHub::Location.look_up(actor_ip)
    end
  end

  def actor_location?
    actor_location.present? && actor_location["country_code"].present?
  end

  # Public: Determine if the actor ip address is an external IP.
  #
  # Returns true if not 127.0.0.1, false if
  def external_ip?
    actor_ip && actor_ip != "127.0.0.1"
  end

  # Public: Determine if the actor ip address is a private/internal IP.
  #
  # default false on enterprise
  # Returns true if part of an internal IP address
  def internal_ip?
    return false if GitHub.enterprise?

    actor_ip && INTERNAL_IP_ADDRESSES.any? { |cidr| cidr.include?(actor_ip) }
  end

  def location?
    location.present?
  end

  def public_repo?
    public_repo == true || public_repo == "true"
  end

  # A much shorter version of `#geolocation`
  #
  # Returns a String
  def country
    location[:country_name] if location?
  end

  def country_code
    location[:country_code] if location?
  end

  # Public: Returns a Float duration for the event.
  def duration
    data["timing"]["duration"]
  end

  # Public: Returns the Minimizable object for the event if one exists
  def minimizable
    @minimizable ||= data["minimizable_type"] ? data["minimizable_type"].constantize.find_by(id: data["minimizable_id"]) : nil
  end

  # Public: Returns the commit comment for the event if one exists
  def commit_comment
    @commit_comment ||= CommitComment.find_by(id: data["commit_comment_id"] || commit_comment_id)
  end

  # Public: Returns the issue comment for the event if one exists
  def issue_comment
    @issue_comment ||= IssueComment.find_by(id: data["issue_comment_id"] || issue_comment_id)
  end

  # Public: Returns the issue for the event if one exists
  def issue
    @issue ||= Issue.find_by(id: data["issue_id"] || issue_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
  end

  def issue_transfer
    issue_transfer_id = hit.data.dig(:issue_transfer, :issue_transfer, :id)
    @issue_transfer ||= IssueTransfer.find_by(id: issue_transfer_id)
  end

  # Public: Returns the discussion for the event if one exists
  def discussion
    @discussion ||= Discussion.find_by(id: data["discussion_id"] || discussion_id)
  end

  # Public: Returns the discussion comment for the event if one exists
  def discussion_comment
    @discussion ||= DiscussionComment.find_by(id: data["discussion_comment_id"] || discussion_comment_id)
  end

  # Public: Returns the project for the event if one exists
  #
  # Project is either a string set on instantiation by new_from_hash(), or an object set here or externally by preload_associations()
  def project
    if memex_project?
      @project ||= MemexProject.find_by(id: data["project_id"] || project_id || data["memex_project_id"])
    else
      @project ||= Project.find_by(id: data["project_id"] || project_id)
    end
  end

  # Public: Returns true if this is a memex project type event
  #
  # Memex projects and legacy projects both have project_id and share similarly named "project.action" audit log entries.
  # We can distinguish Memex project audit log entries by the presence of catalog_service: "github/memex" or project_kind: "MemexProject".
  def memex_project?
    return false unless data
    return true if data["catalog_service"] == "github/memex" || data["project_kind"] == "MemexProject" || data["memex_project_id"]

    # Detect security logs created before a fix was merged on 2022-12-01 for https://github.com/github/memex/issues/11043
    # to correct previously erroneously exposed private projects
    fix_time = Time.new(2022, 12, 2).to_i * 1000
    is_event_before_fix = @created_at && @created_at < fix_time
    (data["catalog_service"] == "github/projects" || data["catalog_service"] == "github/projects_classic") && data["controller_action"] == "migrate" && is_event_before_fix
  end

  # Public: Returns the Marketplace listing for the event if one exists
  def marketplace_listing
    @marketplace_listing ||= Marketplace::Listing.
      find_by(id: data["marketplace_listing_id"] || marketplace_listing_id)
  end

  # Public: Returns the Marketplace listing plan for the event if one exists
  def marketplace_listing_plan
    @marketplace_listing_plan ||= Marketplace::ListingPlan.
      find_by(id: data["marketplace_listing_plan_id"] || marketplace_listing_plan_id)
  end

  # Check if this entry should not be shown to users
  #
  # Returns a boolean
  def hidden_from_users?
    return true if hidden?
    !self.class.user_action_names.include?(action)
  end

  # Check if this entry should not be shown to organizations
  #
  # Returns a boolean
  def hidden_from_orgs?
    return true if hidden?

    !self.class.organization_action_names.include?(action)
  end

  # Check if this entry should not be shown to businesses
  #
  # Returns a boolean
  def hidden_from_businesses?
    return true if hidden?

    if GitHub.single_business_environment?
      !self.class.business_server_action_names.include?(action)
    else
      !self.class.business_cloud_action_names.include?(action)
    end
  end

  # An octicon for use when displaying a list of audit log entries
  #
  # Returns a String containing an octicon name
  def icon
    namespace, event = action.split "."
    I18n.translate(action, default: [:"#{namespace}.default", :default],
                           scope: [:audit_log_entry, :icon])
  end

  def title_with_action(viewer:)
    title = title(viewer: viewer)

    if title
      "#{action}: #{title}"
    else
      action
    end
  end

  # A human-consumable summary of the audit log event. Text comes from
  # config/locales/audit_log_entry.en.yml.
  #
  # Returns a String
  def title(viewer:)
    return @title if @title

    # Repo destroy only has a title if it was a private fork deletion
    if action == "repo.destroy" &&
      (!data["fork_parent"] || data["visibility"] != "private")
      return
    end

    namespace, event = action.split "."

    # Fetch data and mix in the args we need for `I18n.translate` to work
    vals = data_for_i18n(viewer).merge({
      default: [:"#{namespace}.default", :default],
      scope: [:audit_log_entry, :title],
    })

    @title = I18n.translate(action, **vals)
  rescue I18n::MissingInterpolationArgument => e
    @title = ""
  end

  # Check if this entry should be shown.
  #
  # Returns a Boolean.
  def hidden?
    invalid?
  end

  # Public: tells whether or not the audit entry has been marked as invalid.
  # Invalid entries are not shown to regular users.
  #
  # Returns Boolean
  def invalid?
    data && data["_invalid"]
  end

  # Public: Gets the username of the GitHubber who marked this entry as invalid.
  #
  # Returns a string of the username if entry is invalid or nil if not invalid.
  def marked_invalid_by
    return if !invalid?

    data["_invalid_actor"].presence || "unknown"
  end

  # Public: Gets the reason why this entry was marked invalid.
  #
  # Returns a string of the reason if entry is invalid or nil if not invalid.
  def marked_invalid_for
    return if !invalid?

    data["_invalid_reason"]
  end

  def marked_invalid_at(time_zone: Time.zone)
    return if !invalid?

    ms = data["_invalid_at"].to_i
    timestamp Time.at(ms / 1000), time_zone
  end

  # Public: Get the types of repositories that may be created given the
  # visibility value in the audit log entry.
  #
  # value - String representing the `visibility` value in the audit log entry.
  #         See Configurable::MembersCanCreateRepositories for available values.
  #
  # Returns String.
  def members_can_create_repositories_visibility(value)
    case value
    when Configurable::MembersCanCreateRepositories::PUBLIC
      "only private and internal"
    when Configurable::MembersCanCreateRepositories::PRIVATE
      "only public and internal"
    when Configurable::MembersCanCreateRepositories::INTERNAL
      "only public and private"
    when Configurable::MembersCanCreateRepositories::PUBLIC_INTERNAL
      "only private"
    when Configurable::MembersCanCreateRepositories::PRIVATE_INTERNAL
      "only public"
    when Configurable::MembersCanCreateRepositories::PUBLIC_PRIVATE
      "only internal"
    else
      "public, private, and internal"
    end
  end

  def display_actor_location?(viewer)
    return false if integration_installation?
    return false unless performed_by_viewer?(viewer)
    return false if performed_by_staff?
    return false if action == "repo.add_member"
    true
  end

  def integration_installation?
    action.start_with?("integration_installation")
  end

  # Public: Is this event's actor_id the same as the viewer's id?
  def performed_by_viewer?(viewer)
    actor_id.present? && actor_id == viewer&.id
  end

  # Public: Whether this event is considered a staff event based on staff_actor & actor fields.
  def performed_by_staff?
    # If guard_audit_log_staff_actor? is false, no event is considered a staff event.
    return false unless GitHub.guard_audit_log_staff_actor?

    staff_actor_id.present? || staff_actor.present? ||
      actor_id == User.staff_user.id || hit[:actor] == User.staff_user.login
  end

  # Public: The inverse of performed_by_staff?
  def performed_by_non_staff?
    !performed_by_staff?
  end

  def show_country?
    performed_by_non_staff? && !country_hide_action?
  end

  def country_hide_action?
    # This is now maintained in https://github.com/github/audit-log-allowlists
    # If any changes are needed they should be made in that repository then sync'd here
    # To test changes locally, the file in lib/audit/actions_hide_country.rb can be modified but not checked in
    ::Audit::ActionsHideCountry::ACTIONS.include? action
  end

  def before_public_repo_cutoff?
    at_timestamp < PUBLIC_REPO_CUTOFF
  end

  def ip_safe_action?
    ::Audit::ActionsIpSafe::ACTIONS.include?(action)
  end

  def is_emu?
    !!business&.enterprise_managed_user_enabled?
  end

  def disclose_actor?
    action != "business.proxy_security_header_unsatisfied"
  end

  private

  # Keep track of entries created later than 2014-08-21 00:00:00 -0700
  def recently_created?
    @created_at && @created_at / 1000 > 1408604400
  end

  def show_self_metadata?(current_user)
    # The event `repo.add_member` captures user's IP and location and wrongly
    # attributes it to the actor. This leaks sensitive user data to the actor.
    # Temporary fix is to hide self metadata from the actor for this event.
    current_user&.id == metadata[:actor_id] && metadata[:action] != "repo.add_member"
  end

  def instrument_missing_actor
    @instrument_missing_actor ||= begin
      GitHub.dogstats.increment("audit_log_entry", tags: ["error:missing_actor", "action:#{action}", "recent:#{recently_created?}"])
    end
  end

  # Fetches metadata to be passed into `I18n.translate` for interpolation.
  # This hash contains default values for all possible lookups, in case the
  # logged data is missing them (which happens often with older log entries)
  #
  # Returns a Hash
  def data_for_i18n(viewer)
    # We start with some blank defaults because some old events may not have
    # the necessary data.  These will be replaced in the merge calls if there
    # is real data available
    vals = {
      ability_action: "",
      access: "",
      application_name: "",
      oauth_application: "",
      country_code: "",
      creator: "",
      discussion_post_number: "",
      email: "unknown email",
      error: "",
      fingerprint: "",
      fork_parent: "",
      name: "",
      name_id: "",
      note: "",
      old_email: "",
      old_login: "",
      old_name: "",
      old_user: "",
      old_value: "",
      reason: "",
      repo: "",
      gist: "",
      team: "",
      title: "",
      user: "",
      value: "",
      explanation: "",
      topic: "",
      # Defaults for modifications to sso_response message, since old logs will not have new values
      protocol: "SAML",
      id_column_name: "NameID",
      external_id: "",
    }
    # Defaults for modifications to sso_response message, since old logs will not have new values
    if action == "business.sso_response"
      vals[:external_id] = data["name_id"] unless data["external_id"].present?
    end

    vals.merge! self.sanitized_metadata(viewer)
    vals.merge!(data.symbolize_keys) if data

    # Email is a special case, we need to flatten it down if it's a hash
    vals[:email] = vals[:email]["email"] if vals[:email].is_a? Hash

    # Country code is a special case since it comes from the location hash
    vals[:country_code] = self.country_code

    # Sometimes SSH keys have a title, that's nice to include
    unless vals[:fingerprint].blank? || vals[:title].blank?
      vals[:fingerprint] = "#{vals[:title]} - #{vals[:fingerprint]}"
    end

    if oauth_action?(vals[:action])
      if vals[:application_id] == OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
        vals[:application_type] = "Personal access token"
      else
        vals[:application_type] = "OAuth application"
      end
    end

    # Clarify how an OAuth access was deleted by looking up a full textual
    # explanation of the event.
    if oauth_destroy_action?(vals[:action]) && vals[:explanation]
      vals[:explanation] = OauthUtil.destroy_explanation(
        vals[:explanation].to_sym,
      )
    end

    if vals[:action] == "public_key.unverify" && vals[:explanation]
      vals[:explanation] = PublicKey::VALID_UNVERIFY_REASONS[vals[:explanation].to_sym]
    end

    vals
  end

  def oauth_destroy_action?(action)
    action == "oauth_access.destroy" || action == "oauth_authorization.destroy"
  end

  def oauth_action?(action)
    action =~ /\Aoauth_(access|authorization)\./
  end
end
