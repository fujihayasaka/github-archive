# typed: true
# frozen_string_literal: true

module Api::App::FeatureFlagsDependency
  extend T::Helpers
  requires_ancestor { Api::App }

  # If a adding a new preview flag, register it in:
  # https://github.com/github/ecosystem/blob/master/docs/api/REST-previews.md
  # Note: new flags should be named after comic book characters.

  # Internal: Check whether the current user can access staff-shipped
  # functionality.
  #
  # Returns a Boolean value.
  def preview_features?
    return false unless logged_in? && current_user.preview_features?

    return true if !current_user.using_oauth_application?

    current_user.oauth_application.github_owned?
  end
  private :preview_features?

  # Internal: Ensure that staff-only features cannot be previewed by
  # unauthorized users.
  #
  # Halts with a 404 if the request is not authorized for preview features.
  #
  # Returns nothing.
  def preview_features_only
    deliver_error!(404) if !preview_features?
  end
  private :preview_features_only

  # Internal: Halts the request with a 415 (Unsupported Media Type), providing a
  # response for a request that failed to specify the necessary media type when
  # when attempting to access a preview feature.
  #
  # options - The Hash options used to customize the response.
  #           :feature           - The String name of the feature that the
  #                                request attempted to access.
  #           :documentation_url - The String URL for the feature's
  #                                documentation, describing how to access the
  #                                feature.
  #
  # Examples
  #
  #   deliver_preview_access_error! :feature => "Search API",
  #     :documentation_url => "/v3/search"
  #
  # Returns nothing.
  def deliver_preview_access_error!(options = {})
    feature_name = options[:feature]

    message = "If you would like to help us test the #{feature_name} during " \
      "its preview period, you must specify a custom media type in the "      \
      "'Accept' header. Please see the docs for full details."

    deliver_error! 415, message: message,
      documentation_url: options[:documentation_url]
  end
end
