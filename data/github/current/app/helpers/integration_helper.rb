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
    if GitHub.flipper[:enterprise_owned_app_management].enabled?(context)
      link_to "New GitHub App",
              T.unsafe(self).gh_new_settings_app_path(context),
              "class" => new_integration_button_classes(context, ["btn iconbutton BtnGroup-item float-right"]),
              "data-pjax" => true
    end
  end
end
