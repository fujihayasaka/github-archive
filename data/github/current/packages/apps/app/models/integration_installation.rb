# typed: true
# frozen_string_literal: true

require "apps/installation_instrumenter"
require "apps/k_v"

class IntegrationInstallation < ApplicationRecord::Domain::Integrations
  VALID_TARGET_TYPES = %w(User Business)
  MAX_REPOS_TO_INSTRUMENT = 100
  PERMISSIONS_CACHE_TTL = 1.week

  include GitHub::Relay::GlobalIdentification

  include Ability::Actor
  include AuthenticationTokenable
  include GitHub::FlipperActor
  include GitHub::VexiActor
  include IntegrationInstallable
  include ProgrammaticActor::PermissionGrantable

  belongs_to :integration
  belongs_to :target, polymorphic: true

  belongs_to :subscription_item, class_name: "Billing::SubscriptionItem"

  belongs_to :integration_install_trigger

  # rubocop:todo Rails/InverseOf
  belongs_to :version,
    class_name: "IntegrationVersion",
    foreign_key: :integration_version_id
  # rubocop:enable Rails/InverseOf

  belongs_to :user_suspended_by, class_name: "User"

  # HookEventSubscriptions representing the event types that this installation
  # is subscribed to.
  has_many :event_records,
    as: :subscriber,
    class_name: "HookEventSubscription",
    autosave: true,
    extend: HookEventSubscription::AssociationExtension
  destroy_dependents_in_background :event_records

  has_many :children,
    class_name: "ScopedIntegrationInstallation"
  destroy_dependents_in_background :children

  after_commit :destroy_associated_tokens, on: :destroy

  has_many :content_references, through: :version

  has_many :permission_records, as: :actor, class_name: "Permission"
  destroy_dependents_in_background :permission_records

  # integration_id, target_id, target_type should be unique UNLESS this is an
  # github app integration that is installed per repo, in which case we want
  # separate installs for the same user/org for different repos
  validates_uniqueness_of :integration_id, scope: [:target_id, :target_type]

  validates_presence_of :integration

  validates_presence_of :target
  validates             :target_type, inclusion: VALID_TARGET_TYPES

  validates_presence_of :integration_version_id
  validates_presence_of :integration_version_number

  after_validation :sanitize_event_records_name_error

  after_update_commit :instrument_contact_email_changed, if: :saved_change_to_contact_email_id?

  after_destroy :clear_subscription_item_installation

  attribute :integrator_suspended_at, :utc_timestamp
  attribute :user_suspended_at,       :utc_timestamp

  scope :most_recent, -> { order("integration_installations.id DESC") }

  scope :since, -> (time) { where("integration_installations.created_at >= ?", time) }

  scope :not_suspended, -> { where(integrator_suspended: false, user_suspended_by_id: nil) }
  scope :suspended, -> { where("integrator_suspended = 1 OR user_suspended_by_id IS NOT NULL") }

  delegate :single_file_name,
    :single_file_paths,
    :multiple_single_files?,
    to: :version


  # Public: which installations the given user has access to.
  #
  # user - a User or Bot
  # repository_ids - an optional list of repository IDs to scope the associated repo lookup
  #
  # Returns an ActiveRecord scope of IntegrationInstallations
  def self.with_user(user, repository_ids: nil)
    IntegrationInstallation::UserAssociatedInstallations.associated_installations(user: user, repository_ids: repository_ids)
  end

  # IntegrationInstallations with org-level permissions.
  def self.with_org_permissions(org)
    raise ArgumentError, "Organization required" if org.nil?
    with_resources_on(subject: org, resources: Organization::Resources.subject_types)
  end

  scope :with_target, lambda { |target|
    where(target_id: target.id, target_type: target.class.base_class)
  }

  scope :with_target_id_type, lambda { |id, type|
    where(target_id: id, target_type: type)
  }

  # Excludes installations of internal Integrations that are configured as not user-installable.
  scope :user_installable, ->(internal_apps_query = Apps::Privileged::Query.new) {
    # Gets around:
    # DEPRECATION WARNING: Class level methods will no longer inherit scoping from `user_installable` in Rails 6.1. To continue using the scoped relation, pass it into the block directly.
    scoping do
      not_installable = internal_apps_query.without_capability(:user_installable, type: Integration)
      return all if not_installable.empty?
      where.not(integration_id: not_installable)
    end
  }

  def self.ability_type
    self.name
  end

  def adminable_by?(actor)
    IntegrationInstallation::Permissions.check(installation: self, actor: actor, action: :admin).permitted?
  end

  def viewable_by?(actor)
    IntegrationInstallation::Permissions.check(installation: self, actor: actor, action: :view).permitted?
  end

  alias :readable_by? :viewable_by?

  def async_configuration_url(viewer)
    if adminable_by?(viewer)
      if target.organization?
        url = UrlHelpers.settings_org_installations_url(target, host: GitHub.host_name)
      elsif target.user?
        url = UrlHelpers.settings_user_installations_url(host: GitHub.host_name)
      end

      URI.parse(T.must(url))
    else
      async_integration.then do |integration|
        URI.parse(UrlHelpers.edit_alias_app_installation_url(integration, self, host: GitHub.host_name))
      end
    end
  end

  def self.for_actions(repository)
    with_repository(repository).joins(:integration).where(integrations: { id: GitHub.launch_github_app&.id })
  end

  def self.lock_target_for_deletion(record)
    Apps::KV.store.setnx(target_deletion_lock_key(record), Time.now.rfc3339, expires: 30.seconds.from_now)
  end

  def self.target_locked_for_deletion?(record)
    Apps::KV.store.exists(target_deletion_lock_key(record)).value { false }
  end

  def self.target_deletion_lock_key(record)
    # This prevents loading the target (which may have been deleted) when
    # we are able to use the fields available on the integration installation
    identifier = if record.is_a?(IntegrationInstallation)
      "#{record.target_type}:#{record.target_id}"
    else
      "#{record.class.base_class}:#{record.id}"
    end

    "integration_installation:lock:#{identifier}:deleted"
  end

  def outdated?
    return @result if defined?(@result)
    @result = !!(integration_version_number < T.must(integration).latest_version.number)
  end

  # Public: Get the organization that this is installed on.
  #
  # Returns an Organization, or nil if this is not installed on an organization.
  def organization
    target if target && target.organization?
  end

  # Can the GH App be a granted an Ability or UserRole over a given subject?
  # A GH App can only be granted a subset of the permissions that the owner user is allowed to perform over the subject.
  # So there is no need for additional guards when granting permissions.
  def can_be_granted_permission_over!(subject, action); end

  # Public: The collection of event names that this installation subscribes to.
  #
  # Example
  #   events
  #   # => ["issues", "pull_request"]
  #
  # Returns an Array
  def events
    T.unsafe(event_records).names
  end

  # Public: Set the collection of event names this installation should subscribe
  # to.
  #
  # event_names - An Array of event names.
  #
  # Returns an Array of subscribed event names.
  def events=(event_names)
    T.unsafe(event_records).names = event_names
  end

  def target_type=(class_name)
    super(class_name.constantize.base_class.to_s)
  end

  # Public: Grant and remove access to repositories for this installation
  #
  # repositories: - An Array of Repositories to include in the installation.
  # editor:       - The User performing the installation edit.
  # entry_point:  - Object: The `self` of the code calling this method. Used
  #                 for instrumentation.
  #
  # Returns an IntegrationInstallation::Editor::Result.
  def edit(repositories:, editor:, entry_point:)
    IntegrationInstallation::Editor.perform(
      self,
      repositories: repositories,
      editor: editor,
      entry_point: entry_point
    )
  end

  # Public: Update permissions and events for this installation.
  #
  # editor:       - The User performing the installation edit.
  # version       - The IntegrationVersion that the installation
  #                 is being updated to.
  # entry_point:  - The entry point to tag permission writes with
  #
  # Returns an IntegrationInstallation::PermissionsEditor::Result.
  def update_version(editor:, version:, entry_point:)
    IntegrationInstallation::PermissionsEditor.perform(
      self,
      editor: editor,
      version: version,
      entry_point: entry_point,
    )
  end

  CANNOT_AUTO_UPGRADE_ERROR_MESSAGE = "This installation cannot be auto upgraded".freeze

  def auto_update_version(editor:, version:, entry_point:)
    if auto_upgradeable_to?(version)
      return update_version(editor: editor, version: version, entry_point: entry_point)
    end

    error = IntegrationInstallation::PermissionsEditor::Result::Error.new(CANNOT_AUTO_UPGRADE_ERROR_MESSAGE)
    IntegrationInstallation::PermissionsEditor::Result.failed(error)
  end

  # Public: Determine if the given installation be upgraded
  # to the new version without permission from
  # the target.
  #
  # Returns a Boolean.
  def auto_upgradeable_to?(version_to_upgrade_to)
    IntegrationInstallation::Permissions.check(
      installation: self,
      actor:        nil,
      action:       :auto_upgrade,
      version:      version_to_upgrade_to,
    ).permitted?
  end

  # Public: Recalculate the rate limit for this installation.
  #
  # Returns nil.
  def recalculate_rate_limit
    new_rate_limit = IntegrationInstallation::RateLimitCalculator.calculate(self)

    ActiveRecord::Base.connected_to(role: :writing) do
      update(dynamic_rate_limit: new_rate_limit)
    end
  end

  # Public: Remove the installation.
  #
  # actor - The User performing the uninstall (optional).
  #
  # Returns a Boolean.
  def uninstall(actor: nil, staff_actor: false)
    attributable_actor = if staff_actor
      GitHub.guarded_audit_log_staff_actor_entry(actor)
    else
      actor
    end

    generate_webhook_payload(actor: attributable_actor)

    if ActiveRecord::Base.connected_to(role: :writing) { self.destroy }
      instrument_deletion(actor: attributable_actor)
      queue_webhook_delivery

      return true
    end

    false
  end

  # Internal: Get the default level of permission for the specified resource
  #           across all repositories.
  #
  # resource:   - A String to represent a child association, from
  #               Repository::Resources.subject_types, to get the level of permission for.
  # group:      - A String for which type of repositories: currently only 'private'.
  #
  # Returns a Integer action value representing the ability action
  def default_repository_permission(resource:, group: "private")
    raise ArgumentError if Repository::Resources.subject_types.exclude?(resource)

    subject = target.repository_resources.public_send(resource.to_s)
    action = Authorization.service.most_capable_action_between(actor: self, subject: subject)

    if action
      Ability.actions[action]
    end
  end

  def repository_installation_required?
    # Use a temporary version instead of the actual `version` so that we
    # are only using the permissions granted to the installation.
    T.must(integration).repository_installation_required?(target, IntegrationVersion.new(default_permissions: permissions))
  end

  # IntegrationInstallations default to the global default rate limit, but an
  # installation can also be granted a higher rate limit to get more calls. Use
  # #set_temporary_rate_limit to set a 3-day rate limit increase for initial
  # imports and that kind of thing.
  #
  # temporary_rate_limit - A limit that expires after a certain period of time.
  # rate_limit           - A permanent rate limit override set in stafftools.
  # dynamic_rate_limit   - The rate limit calculated based on the target's
  #                        number of resources. See the #recalculate_rate_limit
  #                        method.
  #
  # Returns the currently active rate limit integer value for calls per hour
  def rate_limit
    overridden_rate_limit = temporary_rate_limit || self[:rate_limit]
    return overridden_rate_limit if overridden_rate_limit

    if dynamic_rate_limit && T.must(dynamic_rate_limit) > GitHub.api_default_rate_limit
      return dynamic_rate_limit
    end

    GitHub.api_default_rate_limit
  end

  def temporary_rate_limit
    if temporary_rate_limit_expires_at && T.must(temporary_rate_limit_expires_at).future?
      self[:temporary_rate_limit]
    end
  end

  def set_temporary_rate_limit(limit, duration = 3.days)
    update! temporary_rate_limit: limit, temporary_rate_limit_expires_at: duration.from_now
  end

  def using_temporary_rate_limit?
    temporary_rate_limit.present?
  end

  include Instrumentation::Model

  def event_prefix
    :integration_installation
  end

  def event_payload
    {}.tap do |payload|
      payload[:installation_id]       = id
      payload[:application_client_id] = integration&.key
      payload[:integration]           = integration
      payload[:app]                   = integration
      payload[:name]                  = integration&.name
      payload[:slug]                  = integration&.slug
      payload[:repository_selection]  = repository_selection

      if target.present?
        payload[target.event_prefix] = target
      end
    end
  end

  def instrument_deletion(actor:)
    options = {}
    # The hash case is for pregenerated guarded staff actor entries
    if actor.is_a?(Hash)
      options.merge!(actor)
    elsif actor.present?
      options[:actor_id] = actor.id
      options[:actor] = actor
    end

    options[:permissions] = permissions if integration&.feature_enabled?(:instrument_integration_installation_with_permissions)

    instrumenter = Apps::InstallationInstrumenter.new(self)
    payload = event_payload.merge(options)

    instrumenter.instrument_deletion(payload)
  end

  # Internal: Send instrumentation details about the repositories added to this
  # installation. This method can be called either as part of a web request or
  # via a background job that it self-enqueues to move processing of large
  # numbers of repositories out of the request.
  #
  # repository_ids       - Array of integers representing the added repos
  # actor                - User responsible for making this change
  # repository_selection - "all" or "selected"
  # pending_request      - The IntegrationInstallationRequest that caused this update (optional).
  # async                - Should the instrumentation be done asynchronously?
  # performed_automatically - Was this performed outside of the normal user flow by GitHub?
  #
  # Returns nothing.
  def instrument_repositories_added(repository_ids, actor:, repository_selection:, requester_id: nil, async: true, performed_automatically: false)
    return if repository_ids.blank?
    repository_ids = repository_ids.sort

    options = {
      repositories_added:   repository_ids,
      repository_selection: repository_selection,
      requester_id:         requester_id,
    }

    audit_actor = performed_automatically ? bot : actor
    repo_added_names = Repositories::Public.
      load_repositories(repository_ids).
      order(:id).
      select(:id, :name, :owner_login).
      map(&:name_with_display_owner)

    options[:actor] = audit_actor
    options[:actor_id] = audit_actor.try(:id)
    options[:repositories_added_names] = repo_added_names

    if performed_automatically
      options[:added_automatically] = true
    end

    if instrument_async?(repository_ids, async)
      IntegrationInstallationInstrumentationJob.perform_later(
        :repositories_added,
        T.must(self.id),
        options[:actor_id],
        options[:repositories_added],
        options[:repository_selection],
        requester_id: options[:requester_id],
      )
    else
      # Default instrumentation
      IntegrationInstallation::UserAssociatedRepositories.invalidate_cache(installation: self)

      instrumentation_configurations = {
        repository_selection: repository_selection,
        repository_ids: repository_ids,
        actor: audit_actor
      }

      instrumenter = Apps::InstallationInstrumenter.new(self)
      payload = event_payload.merge(options)

      instrumenter.instrument_repositories_added(payload, instrumentation_configurations)
    end

    # This is not actually a timing, but we want the same kind of
    # information, i.e. average/percentile number of repositories per change.
    GitHub.dogstats.timing "integration_installation.repositories", repository_ids.size, tags: ["action:added"]
  end

  # Internal: Send instrumentation details about the repositories removed from
  # this installation. This method can be called either as part of a web
  # request or via a background job that it self-enqueues to move processing of
  # large numbers of repositories out of the request.
  #
  # repository_ids  - Array of integers representing the removed repos
  # actor           - User responsible for making this change
  # async           - Should the instrumentation be done asynchronously?
  #
  # Returns nothing.
  def instrument_repositories_removed(repository_ids, actor:, async: true, repository_selection: "selected")
    return if repository_ids.blank?
    repository_ids = repository_ids.sort

    repo_removed_names = Repositories::Public.
      load_repositories(repository_ids).
      order(:id).
      select(:id, :name, :owner_login).
      map(&:name_with_display_owner)

    options = {
      actor:                 actor,
      actor_id:              actor.id,
      repositories_removed:  repository_ids,
      repository_selection:  repository_selection,
      repositories_removed_names: repo_removed_names,
    }

    if instrument_async?(repository_ids, async)
      IntegrationInstallationInstrumentationJob.perform_later(
        :repositories_removed,
        T.must(self.id),
        options[:actor_id],
        options[:repositories_removed],
        options[:repository_selection],
      )
    else
      # Default instrumentation
      IntegrationInstallation::UserAssociatedRepositories.invalidate_cache(installation: self)

      instrumentation_configurations = {
        repository_selection: repository_selection,
        repositories: repository_ids,
        actor: actor
      }

      instrumenter = Apps::InstallationInstrumenter.new(self)
      payload = event_payload.merge(options)

      instrumenter.instrument_repositories_removed(payload, instrumentation_configurations)
    end

    # This is not actually a timing, but we want the same kind of
    # information, i.e. average/percentile number of repositories per change.
    GitHub.dogstats.timing "integration_installation.repositories", repository_ids.size, tags: ["action:removed"]
  end

  CONTACT_ORGANIZATION_OWNER_MESSAGE = " Please contact an Organization Owner.".freeze

  # Public: Can the given user manage this installation?
  #
  #   user                - A User.
  #   for_permissions     - A Hash of permissions, for use for a new Installation object,
  #                         with no saved permissions yet.
  #   for_repositories    - An Array of Repository objects, for use for a new Installation object,
  #                         with no saved repositories yet.
  #   on_all_repositories - A Boolean signifying if the installation is on the target (defaults to false).
  #
  # Returns an Array with a result Boolean and an error message String.
  def manageable_by?(user, for_permissions: nil, for_repositories: nil, on_all_repositories: false)
    verb = new_record? ? "install" : "modify"

    default_error_message = "You do not have permission to #{verb} this app on #{target.display_login}."
    default_error_message += CONTACT_ORGANIZATION_OWNER_MESSAGE if target.organization?

    return [false, default_error_message] unless user.present?

    # Short circuit if we can admin the target.
    return [true, nil] if target.adminable_by?(user)

    # Unless the target is an Organization, short-circuit the rest of the logic.
    return [false, default_error_message] unless target.organization?

    ############################
    # Organization Permissions #
    ############################

    if requires_organization_installation?(for_permissions: for_permissions)
      message = "You cannot #{verb} apps with organization permissions on #{target.display_login}."

      return [false, message + CONTACT_ORGANIZATION_OWNER_MESSAGE]
    end

    ###########################
    # Installing on all repos #
    ###########################

    if on_all_repositories || installed_on_all_repositories?
      message = "You do not have permission to #{verb} apps with all repositories on #{target.display_login}."

      return [false, message + CONTACT_ORGANIZATION_OWNER_MESSAGE]
    end

    ###################################
    # Installing on a subset of repos #
    ###################################

    for_repositories ||= repositories
    can_admin_repositories = (for_repositories.present? && for_repositories.all? { |repo| repo.adminable_by? user })

    return [true, nil] if can_admin_repositories

    message = "You do not have permission to #{verb} this App on all repositories belonging to #{target.display_login}."

    [false, message + CONTACT_ORGANIZATION_OWNER_MESSAGE]
  end

  def requires_organization_installation?(for_permissions: nil)
    for_permissions ||= permissions
    Organization::Resources.subject_types.any? { |type| for_permissions.include?(type) }
  end

  def installed_automatically?
    !integration_install_trigger_id.nil?
  end

  def repository_permissions_only?
    # Use a temporary version instead of the actual `version` so that we
    # are only using the permissions granted to the installation.
    T.must(integration).repository_permissions_only?(IntegrationVersion.new(default_permissions: permissions))
  end

  def should_follow_moved_repo?(new_owner:)
    Apps::Privileged.capable?(:follow_repository_transfers, app: integration)
  end

  # Public: the set of permissions associated with the installation.
  #
  # Runs an experiment to determine if we should use the cached permissions
  # in the context of token creation.
  #
  # REF: https://github.com/github/ecosystem-apps/issues/5224
  #
  # Returns a Hash
  def permissions_or_cached_permissions
    science "permission_grantable.permissions_or_cached_permissions" do |experiment|
      experiment.use { permissions }
      experiment.try { get_cached_permissions }
    end
  end

  # Public: Retrieve the set of permissions for this installation.
  #
  # This should not in _any_ way be used for authz. This is meant
  # for displaying the result of its parent method to API consumers.
  #
  # Returns a Hash.
  def get_cached_permissions
    GitHub.tracer.in_span("Integration::get_cached_permissions", kind: :internal) do |span|
      stats_key = "integration_installation.permissions_cache"

      if GitHub.flipper[:integration_installation_permissions_cache_ttl].enabled?
        if T.must(self.updated_at) < PERMISSIONS_CACHE_TTL.ago
          # clear_cached_permissions will refresh the updated_at timestamp as well
          clear_cached_permissions
          GitHub.dogstats.increment(stats_key, tags: ["clear_cache:true"])
        end
      end

      result = self.permissions_cache

      unless result.nil?
        GitHub.dogstats.increment(stats_key, tags: ["cache_result:hit"])
        span.set_attribute("gh.installation.permissions.cache_result", "hit")
        return result.deep_transform_values(&:to_sym)
      end

      span.set_attribute("gh.installation.permissions.cache_result", "miss")
      GitHub.dogstats.increment(stats_key, tags: ["cache_result:miss"])
      set_cached_permissions
    end
  end

  # Public: clears the cached permissions for this installation.
  #
  # Returns nothing.
  def clear_cached_permissions
    ActiveRecord::Base.connected_to(role: :writing) do
      self.update(permissions_cache: nil)
      # Rails won't update the `updated_at` column if the value hasn't changed.
      # To properly signal cache invalidation attempts, the installation is explicitly touched.
      self.touch unless self.updated_at_changed?
    end
  end

  def get_cached_repository_selection
    GitHub.tracer.in_span("Integration::get_cached_repository_selection", kind: :internal) do |span|
      stats_key = "integration_installation.repository_selection_cache"

      result = self.repository_selection_cache

      unless result.nil?
        span.set_attribute("gh.installation.repository_selection.cache_result", "hit")
        GitHub.dogstats.increment(stats_key, tags: ["cache_result:hit"])
        return result
      end

      span.set_attribute("gh.installation.repository_selection.cache_result", "miss")
      GitHub.dogstats.increment(stats_key, tags: ["cache_result:miss"])
      set_cached_repository_selection
    end
  end

  def set_cached_repository_selection
    current_repository_selection = self.repository_selection

    ActiveRecord::Base.connected_to(role: :writing) do
      self.update(repository_selection_cache: current_repository_selection)
    end

    current_repository_selection
  end

  def cached_installed_on_all_repositories?
    get_cached_repository_selection == "all"
  end

  # Public: Determine if the installation
  # has been suspended by either the installation
  # target or by the Integration.
  #
  # Returns a Boolean.
  def suspended?
    integrator_suspended? || user_suspended?
  end

  # Public: Determine if the installation's integration
  #
  # Returns a Boolean.
  def integration_suspended?
    return false unless integration

    T.must(integration).suspended?
  end

  # Get the latest suspended_at timestamp.
  #
  # Returns a String or nil.
  def suspended_at
    return unless suspended?

    # If one or the other is `nil` don't bother comparing timestamps.
    return integrator_suspended_at if user_suspended_at.nil?
    return user_suspended_at       if integrator_suspended_at.nil?

    # If both are set then we return the latest timestamp.
    T.must(integrator_suspended_at) > T.must(user_suspended_at) ? integrator_suspended_at : user_suspended_at
  end

  # Returns the latest actor who suspended the installation.
  #
  # Returns a User or nil.
  def suspended_by
    return unless suspended?

    # If one or the other is `nil` don't bother comparing timestamps.
    return self.bot          if user_suspended_at.nil?
    return user_suspended_by if integrator_suspended_at.nil?

    # If both are set then we return the latest actor who suspended the installation.
    T.must(integrator_suspended_at) > T.must(user_suspended_at) ? self.bot : user_suspended_by
  end

  # Public: Determine if the Integration
  # suspended its own installation.
  #
  # Returns a Boolean.
  def integrator_suspended?
    !!(super && integrator_suspended_at)
  end

  def suspend!(user: nil, staff_actor: false)
    suspended_at = Time.zone.now

    options = {}.tap do |opt|
      if user.present?
        actor = staff_actor && GitHub.guard_audit_log_staff_actor? ? User.staff_user : user

        opt[:user_suspended_by] = actor
        opt[:user_suspended_at] = suspended_at
      else
        user = self.bot

        opt[:integrator_suspended]    = true
        opt[:integrator_suspended_at] = suspended_at
      end
    end

    update!(options)

    if staff_actor
      instrument :suspend, GitHub.guarded_audit_log_staff_actor_entry(user)
    else
      instrument :suspend, { actor: user, actor_id: user.id }
    end

    true
  end

  def unsuspend!(user: nil, staff_actor: false)
    options = {}.tap do |opt|
      if user.present?
        opt[:user_suspended_by] = nil
        opt[:user_suspended_at] = nil
      else
        # Set the Bot so that the event always has an actor.
        user = self.bot

        opt[:integrator_suspended] = false
        opt[:integrator_suspended_at] = nil
      end
    end

    update!(options)

    if staff_actor
      instrument :unsuspend, GitHub.guarded_audit_log_staff_actor_entry(user)
    else
      instrument :unsuspend, { actor: user, actor_id: user.id }
    end

    true
  end

  # Public: Determine if a User actor
  # has suspended the installation on
  # behalf of the target.
  #
  # Returns a Boolean.
  def user_suspended?
    !!(user_suspended_by.present? && user_suspended_at)
  end

  def staff_suspended?
    return false unless user_suspended?
    return false unless GitHub.guard_audit_log_staff_actor?

    T.must(user_suspended_by).staff_user?
  end

  private

  # Internal: should we do instrumentation asynchronously?
  #
  # repository_ids  - Array of Integers representing the repos to instrument
  # async           - Boolean, whether to even consider doing this work async
  #
  # Returns a Boolean.
  def instrument_async?(repository_ids, async)
    !!async && repository_ids.count >= MAX_REPOS_TO_INSTRUMENT
  end

  # Private: Serializes this IntegrationInstallation as a webhook payload for any apps
  # that listen for Hook::Event::IntegrationInstallationEvents. Under normal circumstances
  # we deliver webhook events using instrumentation, but this must be called as
  # a before_destroy and uses Hook::Event#generate_payload_and_deliver_later to
  # serialize the webhook payload before the record becomes unavailable.
  #
  # actor - The User who is performing the event (optional).
  def generate_webhook_payload(actor: nil)
    event = Hook::Event::InstallationEvent.new(
      action: :deleted,
      installation_id: id,
      integration_id: integration_id,
      actor_id: (actor.try(:id) || actor&.fetch(:actor_id, nil) || GitHub.context[:actor_id]),
      triggered_at: Time.now,
    )

    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  # Private: Queue the payloads generated above for delivery to Hookshot.
  def queue_webhook_delivery
    return unless defined?(@delivery_system)
    @delivery_system.deliver_later
  end

  def override_rate_limit
    self[:rate_limit] if using_override_rate_limit?
  end

  def using_override_rate_limit?
    self[:rate_limit].to_i > GitHub.api_default_rate_limit
  end

  # Private: Store the permissions for this installation
  # via the permissions_cache column.
  #
  # This should not in _any_ way be used for authz. This is meant
  # for caching results to display later to API consumers.
  #
  # Returns a Hash.
  def set_cached_permissions
    current_permissions = permission_results

    ActiveRecord::Base.connected_to(role: :writing) do
      self.update(permissions_cache: current_permissions)
    end

    current_permissions
  end

  # Internal: An after_destroy callback which nullifies the related
  # subscription item's installed_at
  #
  # Returns nothing
  def clear_subscription_item_installation
    subscription_item&.clear_marketplace_installation
  end

  def sanitize_event_records_name_error
    key = :"event_records.name"
    return unless errors.key?(key)

    errors.delete(key)

    invalid_names = event_records.select { |event_record| event_record.errors.any? }.map(&:name)

    error_message = \
      "The following #{'event'.pluralize(invalid_names.count)} #{'is'.pluralize(invalid_names.count)} invalid: #{invalid_names.join(', ')}."

    errors.add(:base, error_message)
  end

  def destroy_associated_tokens
    total_records = ServerToServerTokens.domain.count_by_authenticatable_id(self.id)
    DestroyAuthenticationTokensJob.perform_later(self.id, self.class.name) if total_records.nil? || total_records.positive?
  end
end
