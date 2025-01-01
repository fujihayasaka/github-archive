# typed: true
# frozen_string_literal: true

class Integrations::PermissionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include GitHub::Memoizer
  attr_reader :integration, :form, :hook, :programmatic_access, :programmatic_access_requested_permissions

  HOOK_EVENT_OVERRIDES = {
    "organization_projects" => "Organization Projects",
    "repository_projects"   => "Repository Projects",
  }.freeze

  INTEGRATOR_EVENT_DESCRIPTIONS = {
    "meta" => "When this App is deleted and the associated hook is removed.",
  }.freeze

  def programmatic_actor
    integration.present? ? integration : programmatic_access
  end

  def disabled_for_all_actions?
    !!attributes[:disabled_for_all_actions]
  end

  def human_event_title(resource, event_type)
    return event_type.humanize unless HOOK_EVENT_OVERRIDES.key?(resource)
    "#{event_type} for #{HOOK_EVENT_OVERRIDES[resource]}".humanize
  end

  def event_docs_url(event)
    anchor = event.event_type
    "#{GitHub.developer_help_url}/webhooks-and-events/webhooks/webhook-events-and-payloads##{anchor}"
  end

  memoize def granted_permissions
    return version.default_permissions if integration.present?
    return programmatic_access_requested_permissions if programmatic_access_requested_permissions

    programmatic_access.active_request_or_grant&.permissions || {}
  end

  def granted_single_files
    version.single_file_paths
  end

  def granted_content_references
    version.default_content_references.keys
  end

  def resource_docs_url(resource)
    Permissions::FineGrainedResources::Metadata.docs_url(resource, programmatic_actor)
  end

  def hook_events_for_resource(resource)
    event_types = Integration::Events.event_types_for_resource(
      resource,
      actor: current_user,
      integration: integration,
    )
    event_types.inject([]) do |result, event_type|
      result << Integration::Events.hook_event_for_event_type(event_type)
    end
  end

  def available_integrator_events
    Integration::Events::INTEGRATOR_EVENTS.each_with_object([]) do |event_type, events|
      feature_flag = Integration::Events::INTEGRATOR_EVENTS_AND_FEATURE_FLAGS[event_type]

      if feature_flag.nil? || feature_enabled?(feature_flag)
        event = Integration::Events.hook_event_for_event_type(event_type)
        events << event
      end
    end.sort_by(&:display_name)
  end

  def event_selected?(event)
    event_type = event.event_type

    if Integration::Events::INTEGRATOR_EVENTS.include?(event_type)
      integration.integrator_events.include?(event_type)
    else
      version.default_events.include?(event_type)
    end
  end

  def events_selected?(resource)
    hook_events_for_resource(resource).any? { |event| event_selected?(event) }
  end

  # Public: whether to show events for these resources.
  #
  # resource  - One or more String representing a supported Integration::Events
  #             resource type. E.g. "issues", or ["issues", "contents"]
  #
  # True if:
  #   * Any of the supplied resources have been selected as a permission.
  #
  # Returns a Boolean.
  def show_events_for_resource?(resources)
    resources = Array.wrap(resources)
    resources.any? do |resource|
      permission_selected?(resource, :read) ||
        permission_selected?(resource, :write) ||
        permission_selected?(resource, :admin)
    end
  end

  def event_types_to_resources
    integration_events.event_types_to_resources
  end

  # Public: Does the given resource have this permission?
  #
  # resource    - String representing the resource: E.g. "metadata", "issues".
  # permission  - Symbol representing the permission: :none, :read or :write.
  #
  # Returns a Boolean.
  def permission_selected?(resource, permission)
    permission == granted_permissions.fetch(resource, :none)
  end

  # Public: the permission that has been granted to the given resource.
  #
  # resource - String representing the resource: E.g. "metadata", "issues".
  #
  # Returns a Symbol.
  def granted_permission(resource)
    granted_permissions.fetch(resource, :none)
  end

  def has_single_files_error?
    integration.errors["single_files.path"].any?
  end

  def has_single_files_length_error?
    integration.errors["single_files.path"].include?("is too long (maximum is 255 characters)")
  end

  def has_single_files_invalid_character_error?
    integration.errors["single_files.path"].include?("contains invalid characters")
  end

  def hide_content_references?
    !granted_permissions.include?("content_references") && !has_content_references_error?
  end

  def has_content_references_error?
    !integration.errors["content_references.value"].empty?
  end

  # Public: the parent of the given resource as a downcased string.
  #
  # E.g. "issues" => "repository", "members" => "organization" etc.
  #
  # Returns a String.
  def resource_parent(resource)
    "#{Permissions::ResourceRegistry.parent_of(resource)}".downcase
  end

  # Public: is the resource a mandatory permission given the currently granted
  # permissions on this Integration.
  #
  # Returns a Boolean.
  def mandatory_permission_selected?(resource)
    return false unless resource == "metadata"
    Repository::Resources.filter(granted_permissions.except(resource)).any?
  end

  def human_event_description(event)
    INTEGRATOR_EVENT_DESCRIPTIONS[event.event_type] || event.description
  end

  def active_hook?
    return hook.active? if hook
    !!(integration.hook&.active?)
  end

  private

  def feature_enabled?(feature_flag)
    current_user_feature_enabled?(feature_flag) ||
      current_integration_feature_enabled?(feature_flag)
  end

  def current_integration_feature_enabled?(feature_flag)
    integration && GitHub.flipper[feature_flag].enabled?(integration)
  end

  def integration_events
    @integration_events ||= Integration::Events.new(actor: current_user, integration: integration)
  end

  def version
    return @version if defined?(@version)
    @version = integration.latest_version

    # If we try to update an integration and it failed,
    # use the version that would've been set so that we can
    # put back the permissions requested in the form.
    if integration.persisted? && !integration.valid?
      attempted_version = integration.versions.last
      @version = attempted_version if attempted_version.new_record?
    end

    @version
  end
end
