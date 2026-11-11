# typed: true
# frozen_string_literal: true

module IntegrationHelper
  DISABLED_CLASS = "disabled".freeze

  extend T::Helpers

  requires_ancestor { ActionView::Base }

  # Public: Image tag for the integrations's avatar. This can be a custom
  # image, but falls back to the integration owner's gravatar.
  #
  # integration - An Integration.
  # size        - Integer size of the image (optional, default: 80).
  # options     - Additional settings for the image, including:
  #     :height - height of the img tag
  #     :width  - width of the img tag
  #     :alt    - alt attribute for the img tag
  #     :force_app_logo - set to true if the GitHub App's logo should be shown and not the
  #                       Marketplace listing's logo
  #
  # Returns an img tag.
  def integration_avatar(integration:, size: 80, **options)
    installation_view = InstallationView.new(
      integratable: integration,
      session: session,
      current_user: T.unsafe(self).current_user
    )
    listing = integration.marketplace_listing
    show_marketplace_logo = unless options[:force_app_logo]
      listing.try(:publicly_listed?) ||
        installation_view.current_user_has_active_subscription_for_marketplace_listing?
    end

    options[:src] = if show_marketplace_logo
      listing.primary_avatar_url(size * 2)
    else
      integration.preferred_avatar_url(size: size)
    end

    options[:height] ||= size
    options[:width] ||= size
    options[:alt] ||= ""

    options.delete(:force_app_logo)
    tag(:img, options)
  end

  def installation_avatar(installation:, size: 80, **options)
    listing = installation.integration.marketplace_listing
    show_marketplace_logo = installation.subscription_item_id.present?

    options[:src] = if show_marketplace_logo
      listing.primary_avatar_url(size * 2)
    else
      installation.integration.preferred_avatar_url(size: size)
    end

    options[:height] ||= size
    options[:width] ||= size
    options[:alt] ||= ""

    options.delete(:force_app_logo)
    tag(:img, options)
  end

  def has_integration_avatar?(integration)
    integration.primary_avatar.present?
  end

  # Public: Return the correct path to submit the avatar request to.
  #
  # integration - an Integration.
  #
  # Returns a String of the relative path.
  def destroy_app_avatar_path(integration)
    if integration.primary_avatar
      return settings_user_avatar_path(integration.primary_avatar.avatar_id)
    end

    T.unsafe(self).gh_settings_app_path(integration)
  end

  # Public: Return the HTML classes for the "New GitHub App" button
  #
  # context - A User representing the current request context
  # classes - an Array of Strings with the default HTML classes
  #
  # Returns a space-separated String with the resulting classes. A "disabled"
  # class might be added if context has reached the max # of apps
  def new_integration_button_classes(context, classes)
    if context.reached_applications_creation_limit?(application_type: Integration)
      classes << DISABLED_CLASS
    end

    classes.join(" ")
  end

  # Public: Return the "New GitHub App" button for the Enterprise Context
  #
  # Context: An instance of Enterprise, User or Organization.
  def new_enterprise_integration_button_for(context)
    link_to "New GitHub App",
            T.unsafe(self).gh_new_settings_app_path(context),
            "class" => new_integration_button_classes(context, ["btn iconbutton BtnGroup-item float-right"]),
            "data-pjax" => true
  end

  def resources_by_parent_for_permissions(view)
    ProgrammaticAccess::ResourceSelectionListComponent::VALID_RESOURCE_PARENTS.each_with_object({}) do |parent, hash|
      list_component = ProgrammaticAccess::ResourceSelectionListComponent.new(resource_parent: parent, view: view)

      resource_parent = parent.name

      if resource_parent && list_component.render?
        hash[resource_parent.downcase] = list_component.resources_with_metadata
      end
    end
  end

  def granted_permissions_by_section(view, resources)
    resources.each_with_object({}) do |(resource_parent, resource_list), hash|
      hash[resource_parent] ||= {}
      resource_list.each do |resource|
        action_key = view.granted_permissions[resource[:name]]
        next unless action_key

        if action_key
          title = resource.dig(:metadata, :title)
          actions = resource.dig(:metadata, :actions)
          hash[resource_parent][title] = actions[action_key] if title && actions
        end
      end
    end
  end

  def resources_and_granted_permissions_by_parent(view)
    resources = resources_by_parent_for_permissions(view)
    permissions = granted_permissions_by_section(view, resources)
    [resources, permissions]
  end

  def integration_permission_selector_props(view, permissions_selection_component, app_mode = nil)
    resources, granted_permissions_with_section = resources_and_granted_permissions_by_parent(view)

    if T.unsafe(self).current_user.feature_flag_enabled?(:fgpat_form_deep_link, default: false)
      raw_query_permissions = parse_permission_params_for_fgpat(view, params, resources)

      if raw_query_permissions.present?
        granted_permissions_with_section = granted_permissions_by_section_from_query(
          view,
          raw_query_permissions,
          resources
        )
      end
    end
    {
      resources: resources,
      view: {
        disabledForAllActions: view.disabled_for_all_actions?,
        grantedPermissions: granted_permissions_with_section,
        integrationView: permissions_selection_component.integration_view?,
        resourceDocsUrl: view.resource_docs_url(nil),
      },
      showSections: {
        repository: permissions_selection_component.show_repository_permissions?,
        organization: permissions_selection_component.show_organization_permissions?,
        user: permissions_selection_component.show_user_permissions?,
        enterprise: app_mode.nil? && permissions_selection_component.show_enterprise_permissions?
      },
      appMode: app_mode
    }
  end

  def parse_permission_params_for_fgpat(view, raw_params, resources)
    permitted_raw_params = if raw_params.respond_to?(:permit!)
      raw_params.permit!.to_h.stringify_keys
    else
      raw_params.to_h.stringify_keys
    end

    valid_permission_names = resources.values.flatten.map { |r| r[:name] }

    permitted_raw_params.each_with_object({}) do |(key, value), acc|
      next unless valid_permission_names.include?(key)
      next if value.blank?

      acc[key.to_sym] = value.to_sym
    end
  end

  def granted_permissions_by_section_from_query(view, raw_permissions, resources)
    result = Hash.new { |hash, key| hash[key] = {} }

    %w[repository organization user enterprise].each { |section| result[section] }

    raw_permissions.each do |resource_key, action_sym|
      resources.each do |parent, resource_list|
        resource = resource_list.find { |r| r[:name].to_s == resource_key.to_s }
        next unless resource

        title = resource.dig(:metadata, :title)
        actions = resource.dig(:metadata, :actions)
        next unless title && actions && valid_deep_link_action?(resource_list, title, action_sym)

        ui_action = actions[action_sym]
        next unless ui_action

        result[parent][title] = ui_action
      end
    end

    result
  end

  def valid_deep_link_action?(resources, ui_label, action_sym)
    full_permission = resources.find { |r| r[:metadata][:title] == ui_label }
    return false unless full_permission

    allowed_actions = full_permission[:metadata][:fgp] || []
    humanized_action = humanized_action_name(action_sym)

    allowed_actions.include?(humanized_action)
  end

  def humanized_action_name(action_sym)
    case action_sym
    when :read then "Read-only"
    when :write then "Read and write"
    when :admin then "Admin"
    else action_sym.to_s.titleize
    end
  end
end
