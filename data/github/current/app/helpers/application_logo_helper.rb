# typed: true
# frozen_string_literal: true

module ApplicationLogoHelper

  TagHelper = T.type_alias { ActionView::Helpers::TagHelper }

  # Public: Image tag for the application's logo. This can be a custom
  # image, but falls back to the application owner's gravatar.
  #
  # Returns an img tag.
  def oauth_application_logo_tag(application, current_user, session, size = 80, options = {})
    installation_view = InstallationView.new(integratable: application, session: session,
                                             current_user: current_user)
    listing = application.marketplace_listing
    show_marketplace_logo = unless options[:force_app_logo]
      listing.try(:publicly_listed?) ||
        installation_view.current_user_has_active_subscription_for_marketplace_listing?
    end

    options[:src] = if show_marketplace_logo
      listing&.primary_avatar_url(size * 2)
    else
      oauth_application_logo_url(application, size * 2)
    end

    options[:height] ||= size
    options[:width] ||= size
    options[:alt] ||= ""

    options.delete(:force_app_logo)

    T.cast(self, TagHelper).tag(:img, options)
  end

  # Public: Get the image url for the application's logo.
  #
  # Returns an img url
  def oauth_application_logo_url(application, size = 80)
    application.preferred_avatar_url(size: size)
  end

  def self.has_logo?(application)
    (application.primary_avatar || application.logo).present?
  end

  # Public: Return the correct path to submit the logo request to
  #
  # app - an OauthApplication obj
  #
  # Returns an string of the relative path
  def destroy_logo_path(app)
    if app.primary_avatar
      UrlHelpers.settings_user_avatar_path(app.primary_avatar.avatar_id)
    else
      app_settings_path(app)
    end
  end

  # Private: Return the correct settings path for orgs or users
  #
  # app - an OauthApplication obj
  #
  # Returns an string
  def app_settings_path(app)
    if app.user.organization?
      UrlHelpers.settings_org_application_path(app.user, app)
    else
      UrlHelpers.settings_user_application_path(app)
    end
  end

  # Public: Return the correct request method to use to submit the destroy
  # logo request
  #
  # app - an OauthApplication obj
  #
  # Returns an string (e.g. put, post)
  def destroy_logo_method(app)
    return "post" if app.primary_avatar
    "put"
  end

  # Public: Return the field name to send for the destroy logo request
  #
  # app - an OauthApplication obj
  #
  # Returns an string of the name of the field
  def destroy_logo_field_name(app)
    return "op" if app.primary_avatar
    "oauth_application[logo_id]"
  end

  # Public: Return the field value to send for the destroy logo request
  #
  # app - an OauthApplication obj
  #
  # Returns an string of the name of the field
  def destroy_logo_field_value(app)
    "destroy" if app.primary_avatar
  end
end
