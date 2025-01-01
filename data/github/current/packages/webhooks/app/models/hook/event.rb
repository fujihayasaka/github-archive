# typed: true
# frozen_string_literal: true

class Hook::Event
  include Hook::Event::AttributesDependency
  include Hook::Event::RegistryDependency
  include Hook::Event::ClusterWaitDependency
  include ::LegacyImportable
  include Hookshot::DeliverJobLogger
  include Scientist
  include GitHub::Memoizer

  # Public: Returns an event class for a given event type.
  #
  # event_type - the type of event (e.g. push, ping)
  #
  # Returns a Hook::Event class
  # Raises NameError if the Hook::Event class is not found.
  sig { params(event_type: String).returns(T.class_of(Hook::Event)) }
  def self.class_for_event_type(event_type)
    "Hook::Event::#{event_type.to_s.camelize}Event".constantize
  end

  # Public: instantiates and returns the correct Hook::Event
  # class for a given event type.
  #
  # event_type - the type of event (e.g. push, ping)
  # attributes - optional attributes to initialize the event with
  #
  # Returns a Hook::Event object
  # Raises NameError if the Hook::Event class is not found.
  sig { params(event_type: String, attributes: Hash).returns(Hook::Event) }
  def self.for_event_type(event_type, attributes = {})
    class_for_event_type(event_type).new(attributes)
  end

  # Public: Queues an event for delivery to Hookshot.
  #
  # arguments  - Hash of arguments needed to build the event
  #
  # Returns true if queued.
  def self.queue(attributes = {})
    event = new(attributes)
    event.attributes[:queued_at] = Time.now.to_f

    # In order to safely read from replicas when processing events, we need to capture information
    # about database writes when the event initially occurs. Later, when we process the event,
    # we can use this information to wait the appropriate amount of time for each DB cluster.
    actor = Hook::EventAsActor.new(self.event_type)
    event.deliver_later
  end

  # Public: Returns the action if any. This should be overridden in each specific Hook::Event model if applicable.
  #
  # Returns a Repository or nil
  sig { returns(T.nilable(Repository)) }
  def action; end

  def initialize(attributes = {})
    attributes = attributes.symbolize_keys
    attributes[:triggered_at] = parse_triggered_at(attributes[:triggered_at])
    attributes[:delivered_hook_ids] ||= []

    super attributes

    serialize_primary_resource(attributes[:primary_resource])
    initialize_tenant
    initialize_primary_resource
  end

  # Public: takes in an instance of the primary resource (e.g. CheckRun)
  # and serializes it "as_json" into a hash to store on the event
  def serialize_primary_resource(primary_resource)
    return unless primary_resource
    self.attributes[:primary_resource_data] = record_query_counts("prehydration_queries") do
      primary_resource.as_json(root: false)
    end
  end

  def prehydrate_primary_webhook_data_enabled?(primary_resource)
    repo_id = primary_resource.is_a?(Hash) ? primary_resource["repository_id"] : primary_resource.try(:repository_id)
    repo = Repository.instantiate("id" => repo_id)
    GitHub.flipper["prehydrate_primary_webhook_data_for_#{event_type}"].enabled?(repo)
  end

  # Public: takes a metric name and a block and sends a DD metric
  # for how many queries, and N+1 queries happened during the block
  def record_query_counts(metric, track_n_plus_one = false, tags = [], &block)
    GitHub::MysqlInstrumenter.with_track do
      original_queries_per_db_count = GitHub::MysqlInstrumenter.queries_per_database.clone
      original_query_count = GitHub::MysqlInstrumenter.queries.size.clone

      return_value = yield

      new_queries_per_db_count = GitHub::MysqlInstrumenter.queries_per_database.clone
      new_query_count = GitHub::MysqlInstrumenter.queries.size.clone

      if new_queries_per_db_count.empty?
        GitHub.dogstats.distribution("hook.event.#{metric}", 0, tags: default_stats_tags + tags)
      else
        new_queries_per_db_count.each do |db, count|
          GitHub.dogstats.distribution("hook.event.#{metric}", (count - original_queries_per_db_count[db].to_i), tags: default_stats_tags + tags + ["cluster:#{db.underscore}"])
        end
      end

      if track_n_plus_one
        mysql_count_diff = new_query_count - original_query_count
        if mysql_count_diff.zero?
          GitHub.dogstats.distribution("hook.event.#{metric}.nplusone", 0, tags: default_stats_tags + tags)
        else
          mysql_calls = GitHub::MysqlInstrumenter.queries[original_query_count, mysql_count_diff]
          n_plus1_queries = Platform::Tracing::Helpers::NPlusOneQueries.get(mysql_calls)
          GitHub.dogstats.distribution("hook.event.#{metric}.nplusone", n_plus1_queries.size, tags: default_stats_tags + tags)
        end
      end

      return_value
    end
  end

  # Public: uses the public_resource_data attribute to set the primary resource
  # ivar after checking a FF
  def initialize_primary_resource
    return false unless attributes[:primary_resource_data]
    return true if prehydrate_primary_webhook_data_enabled?(attributes[:primary_resource_data])

    false

    # Currently does nothing and requires subclasses to override this method.
    # Once we are comfortable with this approach we can remove the overrides
    # in the subclasses and do something like:
    # instance = event_type.constantize.new(public_resource_data)
    # instance_variable_set("@{event_type}", instance)
  end

  # Public: set tenant at the time the event is first triggered/created
  def initialize_tenant
    tenant
  end

  # Public: the tenant which corresponds to the event
  #
  # returns a Business object or nil
  def tenant
    @tenant ||= GitHub::CurrentTenant.get
  end

  # Public: Returns the inferred event type from the event's class name.
  #
  # Examples
  #
  #   Hook::Event::PullRequestEvent.new.event_type => "pull_request"
  #
  # Returns the event type string.
  def event_type
    self.class.event_type
  end

  # Public: Returns if the class event is feature flaged.
  #
  # Returns a boolean
  def feature_flagged?
    self.class.feature_flagged?
  end

  # Public: Returns the actions that are feature flagged.
  #
  # Returns an array.
  def flagged_actions
    self.class.flagged_actions
  end

  # Public: Returns the guid for this event
  #
  def guid
    @guid ||= self.attributes.fetch(:event_guid, nil) || SimpleUUID::UUID.new(T.unsafe(self).triggered_at).to_guid
  end

  # Public: Returns actor to use in feature flag checks.
  #
  # Returns any valid feature flag actor, but typically Organization or Repository.
  def feature_flag_actor
    target_organization || target_repository
  end

  # Public: Returns the repo this event targets if any. This should
  # be overridden in each specific Hook::Event model.
  #
  # Returns a Repository or nil
  def target_repository
  end

  # Public: Returns the organization this event targets if any. Can be
  # overridden by each Hook::Event model. By default it returns the target
  # repo's owner if that owner is an Organization.
  #
  # Returns an Organization or nil
  def target_organization
    return unless target_repository
    return unless target_repository.owner
    return unless target_repository.owner.organization?
    target_repository.owner
  end

  # Public: Returns the business this event targets if any. Can be
  # overridden by each Hook::Event model. By default it returns the target
  # organization's business if it is part of one.
  #
  # Returns a Business or nil
  def target_business
    return GitHub.global_business if GitHub.single_business_environment?
    return unless target_organization

    T.must(target_organization).business
  end

  def delivery_rate_limit_data
    if target_business&.plan.present?
      ["Enterprise:#{target_business.id}", target_business.plan.name]
    elsif target_organization&.plan.present?
      ["Organization:#{target_organization.id}", target_organization.plan.name]
    elsif target_repository&.owner&.plan.present?
      ["User:#{target_repository.owner.id}", target_repository.owner.plan.name]
    else
      [nil, nil]
    end
  end

  # Public: Returns the listing this event targets if any. This should
  # be overridden in each specific Hook::Event model.
  #
  # Returns a Marketplace::Listing or nil
  def target_marketplace_listing
  end

  # Public: Returns the listing this event targets if any. This should
  # be overridden in each specific Hook::Event model.
  #
  # Returns a SponsorsListing or nil
  def target_sponsors_listing
  end

  # Public: Returns the user who triggered this event if any. This should
  # be overridden in each specific Hook::Event model.
  #
  # Returns a User or nil
  def actor
    raise NotImplementedError
  end

  # Public: Finds all hooks which should be triggered for this event.
  #
  # Returns an Array of Hooks.
  def subscribed_hooks
    time_subscribed_hooks("subscribed_hooks") do
      @subscribed_hooks ||= begin
        integration_hooks = subscribed_integration_hooks
        integrator_hooks = subscribed_integrator_hooks
        business_hooks = subscribed_hooks_for_parent(target_business)
        org_hooks  = subscribed_hooks_for_parent(target_organization)
        repo_hooks = subscribed_hooks_for_parent(target_repository)
        marketplace_listing_hooks = subscribed_hooks_for_parent(target_marketplace_listing)
        sponsors_listing_hooks = subscribed_hooks_for_parent(target_sponsors_listing)

        business_hooks | org_hooks | repo_hooks | integration_hooks |
        marketplace_listing_hooks | sponsors_listing_hooks | integrator_hooks
      end
    end
  end

  # Public: Finds and instantiates a payload model for this event.
  #
  # Returns an instance of Hook::Payload
  def payload
    @payload ||= Hook::Payload.for_event(self)
  end

  # Public: Returns the payload hash that should be delivered.
  #
  # Returns a Hash.
  def to_payload_hash
    payload.to_hash
  end

  # Public: Returns any custom HTTP headers that should be attached to this hook delivery.
  #
  # Returns an Array. Each element is a Hash, with a "name" and "value".
  def headers_for(hook)
    headers = []
    if include_tenant_header?
      headers << { "X-GitHub-Tenant" => "#{tenant.slug}" }
      headers << { "X-GitHub-Tenant-ID" => "#{tenant.id}" }
    end
    headers
  end

  # tenant is populated on event initialization IF there is a tenant present in the context
  def include_tenant_header?
    GitHub.multi_tenant_enterprise? && !tenant.nil?
  end

  def log_context
    @log_context ||= {
      "code.filepath" => "packages/webhooks/app/models/hook/event.rb",
      "gh.catalog_service" => "github/webhooks",
      "gh.request_id" => GitHub.context[:request_id],
      "gh.webhook.event_type" => event_type,
      "gh.webhook.action" => attributes[:action],
      "gh.webhook.delivery_guid" => guid
    }
  end

  # Internal: Kicks of the delivery process for the event
  # and all of its subscribed hooks.
  #
  # Returns nothing.
  def deliver
    return if Rails.env.test? && !Hook.delivers_in_test?

    GitHub.dogstats.distribution_time("hooks.jit_deliverability", tags: default_stats_tags) do
      tags = default_stats_tags << "fn:deliver"

      unless feature_flag_enabled?
        GitHub.dogstats.increment("hooks.disabled_by_feature_flag", tags: tags)
        instrument_event_metadata(self, filtered_reason: "disabled_by_feature_flag")
        return
      end

      if target_repository_disallows_hooks?
        GitHub.dogstats.increment("hooks.target_repository_disallows_hooks", tags: tags)
        instrument_event_metadata(self, filtered_reason: "target_repository_disallows_hooks")
        return
      end

      if !deliverable?
        GitHub.dogstats.increment("hooks.non_deliverable", tags: tags)
        instrument_event_metadata(self, filtered_reason: "non_deliverable")
        return
      end

      if importing? || model_importing?
        GitHub.dogstats.increment("hooks.disabled_for_import", tags: tags)
        instrument_event_metadata(self, filtered_reason: "disabled_for_import")
        return
      end
    end

    Hook::DeliverySystem.deliver(self)
  end

  # Internal: Enqueues a job that will deliver the event in the background.
  #
  # Returns nothing.
  def deliver_later
    tags = default_stats_tags << "fn:deliver_later"

    if importing? || model_importing?
      GitHub.dogstats.increment("hooks.disabled_for_import", tags: tags)
      instrument_event_metadata(self, filtered_reason: "disabled_for_import")
      return
    end

    unless feature_flag_enabled?
      GitHub.dogstats.increment("hooks.disabled_by_feature_flag", tags: tags)
      instrument_event_metadata(self, filtered_reason: "disabled_by_feature_flag")
      return
    end

    attributes_size = attributes.to_json(dangerously_allow_all_keys: true).bytesize
    # This is for tracking purposes to determine the size of tier1 events in the future Events V2 system.
    # tier1 events will include both the prehydrated payload and the attributes of the event.
    # In this case, we only track the attributes size as this path does not include any prehydrated payloads.
    GitHub.dogstats.distribution("hooks.tier1_event_size", attributes_size, tags: tags + ["prehydrated:false"])

    DeliverHookEventJob.perform_later(event_type, attributes)
    record_enqueued_metrics
  end

  # Internal: returns whether or not this event is fit to be delivered.
  # Events which need a mechanism for bailing out in certain cases should
  # us this.
  #
  # Returns Boolean.
  def deliverable?
    true
  end

  # Internal: returns whether or not the target repo is locked for migrations.
  #
  # Returns Boolean.
  memoize def model_importing?
    ActiveRecord::Base.connected_to(role: :reading) do
      target_repository&.locked_on_migration? || target_repository&.is_importing?
    end
  rescue ArgumentError, NoMethodError, ActiveRecord::RecordNotFound
    # this means we were unable to retrieve a target repository causing exception.
    # ignore and return false.
    false
  end

  # Internal: Fetch the installation of a given Integration whose hook
  # is subscribed to this event.
  #
  # Returns an Array of IntegrationInstallations.
  def subscribed_installations_for(integration_id)
    target = if target_organization
      target_organization
    elsif target_repository
      target_repository.owner
    end

    return IntegrationInstallation.none unless target.present?

    integration = integration_id.is_a?(Integration) ? integration_id : Integration.find_by(id: integration_id)
    return IntegrationInstallation.none if integration.blank? || integration.suspended?

    scope = IntegrationInstallation.not_suspended.with_target(target).where(integration_id: integration.id)
    filtered_ids = HookEventSubscription.with_name_and_subscriber(event_type, "IntegrationInstallation", scope.ids).pluck(:subscriber_id)
    scope.where(id: filtered_ids)
  end

  # Public: Returns whether or not the target item has the appropriate feature
  # flag enabled.
  #
  # Returns a Boolean.
  def feature_flag_enabled?
    return true unless feature_flagged?
    return true unless flagged_actions.include?(self.try(:action)) if flagged_actions.present?
    return self.class.feature_flag_enabled_for(feature_flag_actor) if feature_flag_actor.present?
    false
  end

  def target_repository_disallows_hooks?
    target_repository&.disabled? || advisory_workspace?
  end

  # Public: Returns whether or not this event can be filtered for Actions integrations
  #
  # Returns a Boolean.
  def filterable_for_actions?
    return false unless target_repository.present?

    Repository::WorkflowsDependency::DEFAULT_BRANCH_EVENTS.include?(event_type)
  end

  # Public: Fetch all integration installations associated with an integration hooks that are subscribed to this event.
  #
  # Finds all application installations that have webhook subscriptions that:
  # - includes the repository associated with this event, or
  # - includes the organization associated with this event, and
  # - includes this event type.
  #
  # Returns an Array of the IntegrationInstallations.
  def self.get_subscribed_integration_installations(event_type:, target_repository:, target_organization:)
    repository_based_installation_ids = []
    if target_repository && ::Integration::Events.repository_event?(event_type)
      # Get the resources that the integrations needs to have access to see the event type
      resources_for_event = Integration::Events.repository_resources_for_event(event_type)

      # Get all integration installation ids on the repo with the required permissions
      repository_based_installation_ids = IntegrationInstallation.ids_with_resources_on(subject_class: Repository, subject_id: target_repository.id, subject_owner_id: target_repository.owner_id, resources: resources_for_event)
    end

    org_based_installation_ids = []
    if target_organization && ::Integration::Events.organization_event?(event_type)
      # Get the resources that the integrations needs to have access to see the event type
      resources_for_event = Integration::Events.organization_resources_for_event(event_type)

      # Get all integration installation ids on the org with the required permissions
      org_based_installation_ids = IntegrationInstallation.ids_with_resources_on(subject_class: Organization, subject_id: target_organization.id, subject_owner_id: nil, resources: resources_for_event)
    end

    installation_ids = repository_based_installation_ids | org_based_installation_ids
    return IntegrationInstallation.none if installation_ids.empty?

    # Filter down to integration installation ids that are subscribed to the given event
    installation_ids = HookEventSubscription.with_name_and_subscriber(event_type, IntegrationInstallation, installation_ids).pluck(:subscriber_id)
    return IntegrationInstallation.none if installation_ids.empty?

    IntegrationInstallation.not_suspended.where(id: installation_ids).distinct
  end

  # Public: Fetch all active integration hooks for the given installation targets.
  #
  # Returns an Array of Hooks.
  def self.get_active_hooks_by_installation_target(installation_target_type:, installation_target_id:)
    Hook.active.where(installation_target_type: installation_target_type, installation_target_id: installation_target_id)
  end

  # Public: Fetch all integration hooks that are subscribed to this event.
  #
  # The org_id takes precendence over the target_organization.
  #
  # Finds all application hooks where the application has an installation that:
  # - includes the repository associated with this event, or
  # - includes the organization associated with this event, and
  # - includes this event type.
  #
  # Returns an Array of Hooks.
  def self.get_subscribed_integration_hooks(event_type:, target_repository:, target_organization:, org_id: nil)
    target_organization = Organization.new(id: org_id) if org_id.present?

    # Map integration installations down to integration ids
    integration_ids = get_subscribed_integration_installations(event_type: event_type, target_repository: target_repository, target_organization: target_organization).pluck(:integration_id)
    return Hook.none if integration_ids.empty?

    integration_ids = Integration.where(id: integration_ids).active.pluck(:id)
    return Hook.none if integration_ids.empty?

    Hook.where(installation_target_type: Integration).where(installation_target_id: integration_ids).active
  end

  private

  # Private: Return the default tags for statsd metrics.
  #
  # Returns an Array of colon separated key/value pairs.
  def default_stats_tags
    @default_stats_tags ||= GitHub::TaggingHelper.create_hook_event_tags(event_type, attributes[:action])
  end

  def parse_triggered_at(time_or_stamp)
    return Time.now unless time_or_stamp.present?
    if time_or_stamp.kind_of?(Time)
      time_or_stamp
    elsif time_or_stamp.kind_of?(Integer)
      Time.at(time_or_stamp)
    else
      Time.parse(time_or_stamp)
    end
  end

  def subscribed_hooks_for_parent(parent)
    return [] unless parent
    time_subscribed_hooks("subscribed_hooks_for_#{parent.class.name.downcase}") do
      if parent.is_a?(Repository) && parent.repo_hook_associations_ff?
        Hook.hooks_for_target(parent).active.to_a.select { |hook| hook.call?(event_type, action: self.try(:action).try(:to_sym)) }
      else
        parent.hooks.active.to_a.select { |hook| hook.call?(event_type, action: self.try(:action).try(:to_sym)) }
      end
    end
  end

  # Internal: Fetch all integration hooks that are subscribed to this event.
  #
  # Finds all application hooks where the application has an installation that:
  # - includes the repository associated with this event, or
  # - includes the organization associated with this event, and
  # - includes this event type.
  #
  # Returns an Array of Hooks.
  def subscribed_integration_hooks
    time_subscribed_hooks("subscribed_integration_hooks") do
      self.class.get_subscribed_integration_hooks(
        event_type: event_type,
        target_repository: target_repository,
        target_organization: target_organization,
        org_id: T.unsafe(self).organization_id
      )
    end
  end

  # Internal: Fetch all integrator hooks that are subscribed to this event.
  #
  # Finds all hooks where the integration is directly subscribed, rather than
  # one of its integration versions or integration installations.
  #
  # Returns an Array of Hooks.
  def subscribed_integrator_hooks
    time_subscribed_hooks("subscribed_integrator_hooks") do
      Hook.subscribed_to_integrator_event(event_type).active
    end
  end

  # Internal: Logs metrics for the event
  #
  # Returns nothing.
  def record_enqueued_metrics
    tags = default_stats_tags << "job:deliver-hook-event"

    GitHub.dogstats.increment("hooks.job_enqueued.count", tags: tags)

    if replication_state = DatabaseSelector::ReplicationState.current&.to_hash
      replication_state.keys.each do |cluster_name|
        GitHub.dogstats.increment("hooks.mysql.cluster.touched", tags: tags + ["cluster:#{cluster_name}"])
      end
    end
  end

  # Internal: Logs metrics for time spent fetching event subscriptions
  #
  # Returns nothing.
  def time_subscribed_hooks(function_name)
    start_time = GitHub::Dogstats.monotonic_time
    yield
  ensure
    elapsed = GitHub::Dogstats.duration(start_time)
    GitHub.dogstats.distribution("hooks.subscribed_hooks.duration", elapsed, tags: default_stats_tags + ["function:#{function_name}"])
  end

  def advisory_workspace?
    target_repository&.advisory_workspace? &&
    !target_repository&.parent_advisory&.repository&.feature_enabled?(:maintainer_love_advisory_workspaces_can_use_actions)
  end
end
