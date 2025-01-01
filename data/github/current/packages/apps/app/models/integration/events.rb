# typed: true
# frozen_string_literal: true

class Integration::Events
  @@feature_flags = {
    "push_ruleset_exemption_request_webhooks" => [:exemption_request_push_ruleset]
  }
  @@internal_events = []

  # Events not available to GHES.
  SUPPORTED_DOTCOM_ONLY_EVENTS = %w(
    org_block
    repository_advisory
    sub_issues
  )

  SUPPORTED_EVENTS = %w(
    branch_protection_configuration
    branch_protection_rule
    code_scanning_alert
    check_run
    check_suite
    commit_comment
    create
    custom_property
    custom_property_values
    discussion
    discussion_comment
    delete
    dependabot_alert
    deploy_key
    deployment
    deployment_protection_rule
    deployment_review
    deployment_status
    exemption_request_push_ruleset
    exemption_request_secret_scanning
    fork
    gollum
    issue_comment
    issues
    installation_target
    label
    milestone
    member
    membership
    merge_group
    merge_queue_entry
    meta
    organization
    page_build
    personal_access_token_request
    project
    project_card
    project_column
    projects_v2_item
    projects_v2
    projects_v2_status_update
    public
    pull_request
    pull_request_review
    pull_request_review_comment
    pull_request_review_thread
    push
    registry_package
    release
    reminder
    repository
    repository_dispatch
    repository_ruleset
    security_and_analysis
    secret_scanning_alert
    secret_scanning_alert_location
    secret_scanning_scan
    star
    status
    team
    team_add
    watch
    workflow_dispatch
    workflow_job
    workflow_run
  )

  # Make sure we don't show dotcom only
  # events to GHES instances.
  unless GitHub.enterprise?
    SUPPORTED_DOTCOM_ONLY_EVENTS.map do |event|
      SUPPORTED_EVENTS.append(event)
    end
  end

  RESOURCE_TO_EVENTS = {
    "actions"                     => %w(workflow_job workflow_run),
    "administration"              => %w(branch_protection_configuration branch_protection_rule repository_ruleset exemption_request_push_ruleset member security_and_analysis),
    "checks"                      => %w(check_suite check_run),
    "contents"                    => %w(commit_comment create delete fork gollum push release repository_dispatch workflow_dispatch workflow_job workflow_run),
    "deployments"                 => %w(deployment deploy_key deployment_protection_rule deployment_status deployment_review),
    "discussions"                 => %w(discussion discussion_comment),
    "issues"                      => %w(issue_comment issues milestone sub_issues),
    "members"                     => %w(member membership organization team team_add),
    "merge_queues"                => %w(merge_group),
    "metadata"                    => %w(label public repository watch star),
    "organization_administration" => %w(org_block repository_ruleset),
    "organization_custom_properties" => %w(custom_property custom_property_values),
    "organization_projects"       => %w(project_card project_column project projects_v2_item projects_v2 projects_v2_status_update),
    "packages"                    => %w(registry_package),
    "organization_personal_access_token_requests" => %w(personal_access_token_request),
    "pages"                       => %w(page_build),
    "pull_requests"               => %w(milestone pull_request pull_request_review pull_request_review_comment pull_request_review_thread reminder merge_queue_entry),
    "repository_advisories"       => %w(repository_advisory),
    "repository_projects"         => %w(project_card project_column project),
    "secret_scanning_alerts"      => %w(secret_scanning_alert secret_scanning_alert_location exemption_request_secret_scanning secret_scanning_scan),
    "security_events"             => %w(code_scanning_alert),
    "statuses"                    => %w(status),
    "vulnerability_alerts"        => %w(dependabot_alert),
  }.freeze

  # Integrator events are those that do not depend on available resources or
  # granted permissions. The information delivered via an integrator event is
  # not always associated with an individual installation or target (repository,
  # organization, etc.). The event is triggered only once for each subscribed
  # integration. Integrator events are not inherited by integration versions
  # nor by integration installations.
  INTEGRATOR_EVENTS = %w(
    security_advisory
    meta
    installation_target
  )

  INTEGRATOR_EVENTS_AND_FEATURE_FLAGS = {}

  attr_reader :actor
  attr_reader :integration

  def initialize(actor:, integration:)
    @actor = actor
    @integration = integration
  end

  # Public: a mapping of event types to the resources applicable to that event.
  # E.g. { "milestone" => ["pull_requests", "issues"], ... }
  #
  # Returns a Hash. Memoizes the event type to resource mapping based on the
  # current actor.
  def event_types_to_resources
    @event_types_to_resources ||= self.class.event_types_to_resources(actor: actor, integration: integration)
  end

  def self.event_types_for_resource(resource, actor: nil, include_all_events: false, integration: nil)
    Array.wrap(RESOURCE_TO_EVENTS[resource]).select do |event|
      next true if include_all_events
      next true unless event_feature_flagged?(event) || internal_event?(event)
      next true if actor.present? && event_feature_enabled?(event, actor: actor)
      integration.present? && internal_event_allowed?(event, integration: integration)
    end
  end

  def self.hook_event_for_event_type(event_type)
    Hook::EventRegistry.for_event_type(event_type)
  end

  # Internal: a mapping of event types to the resources applicable to that event.
  # E.g. { "milestone" => ["pull_requests", "issues"], ... }
  #
  # Returns a Hash.
  def self.event_types_to_resources(actor: nil, integration: nil)
    Integration::Events::SUPPORTED_EVENTS.inject({}) do |events_to_resources, event|
      # Skip this event type if it is behind a feature flag and not enabled for this actor.
      next(events_to_resources) if event_feature_flagged?(event) && !(actor.present? && event_feature_enabled?(event, actor: actor))
      # Skip this event type if it is internal only and not enabled for this integration.
      next(events_to_resources) if internal_event?(event) && !(integration.present? && internal_event_allowed?(event, integration: integration))

      resources = Integration::Events::RESOURCE_TO_EVENTS.select do |_resource, events|
        events.include?(event)
      end.map(&:first)
      events_to_resources[event] = resources
      events_to_resources
    end
  end

  def self.organization_event?(event_type)
    organization_events.include?(event_type)
  end

  def self.repository_event?(event_type)
    repository_events.include?(event_type)
  end

  def self.resources_for_event(event_type)
    RESOURCE_TO_EVENTS.find_all { |_, events| events.include?(event_type) }.map(&:first)
  end

  def self.organization_resources_for_event(event_type)
    resources_for_event(event_type) & Organization::Resources.subject_types
  end

  def self.repository_resources_for_event(event_type)
    resources_for_event(event_type) & Repository::Resources.subject_types
  end

  def self.organization_events
    RESOURCE_TO_EVENTS.select do |resource, _events|
      Organization::Resources.subject_types.include?(resource)
    end.values.flatten
  end
  private_class_method :organization_events

  def self.repository_events
    RESOURCE_TO_EVENTS.select do |resource, _events|
      Repository::Resources.subject_types.include?(resource)
    end.values.flatten
  end
  private_class_method :repository_events

  def self.feature_flag(event, flag)
    (@@feature_flags[flag] ||= []).push(event)
  end

  def self.remove_feature_flag(event, flag)
    @@feature_flags[flag].delete(event)
  end

  def self.feature_flagged_events
    @@feature_flags.values.flatten
  end
  private_class_method :feature_flagged_events

  def self.event_feature_flagged?(event)
    feature_flagged_events.include?(event.to_sym)
  end
  private_class_method :event_feature_flagged?

  def self.event_feature_enabled?(event, actor:)
    @@feature_flags.any? do |flag, events|
      next false unless events.include?(event.to_sym)
      GitHub.flipper[flag].enabled?(actor)
    end
  end
  private_class_method :event_feature_enabled?

  def self.internal_event(event)
    @@internal_events.push(event)
  end

  def self.internal_event?(event)
    @@internal_events.include?(event.to_sym)
  end
  private_class_method :internal_event?

  def self.internal_event_allowed?(event, integration:)
    return false unless internal_event?(event)
    events = Apps::Privileged.property(
      :allowed_internal_events,
      app: integration
    )
    !events.blank? && events.include?(event.to_sym)
  end
  private_class_method :internal_event_allowed?

  internal_event :reminder

  # If you are deploying a new event behind a feature flag, specify the event
  # and corresponding feature flag below. This prevents the event from
  # appearing in the GitHub App UI until the feature flag is enabled.
  #
  # For example:
  #
  #   feature_flag :dependabot_alert, :dependabot_alert_webhook
  #
end
