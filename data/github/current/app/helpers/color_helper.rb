# typed: true
# frozen_string_literal: true

module ColorHelper
  extend T::Helpers

  include FeatureFlagHelper
  include TagAttributeHelper
  include ActionView::Helpers::AssetTagHelper
  include StaticAssetHelper

  requires_ancestor { Object }

  abstract!

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  sig { abstract.returns(T.nilable(ActionDispatch::Request)) }
  def request; end

  # Public: Figures out an appropriate text color given a base color background. Ensures that you
  # don't get black text on a dark red background, etc.
  #
  # Returns a String of a hex color.
  def text_color(color)
    ColorCalculator.new(color).text_color
  end

  # Returns the bundle(s) for the users' current theme.
  #   * If the user has auto mode it returns light and dark theme bundles.
  #   * If the controller requests all themes, it returns all bundles.
  def color_mode_bundles(experimental: false)
    if color_modes_all_themes?
      themes = UserTheme::THEMES.sort_by { |theme| theme.sort }
    elsif (
      feature_enabled_globally_or_for_visitor?(feature_name: :appearance_settings_logged_out_users) &&
      current_user.nil?
    )
      # Load increased-contrast themes for logged-out users, so they’re ready if selected
      themes = %w[light light_high_contrast dark dark_high_contrast]
    elsif ColorMode.disabled?(request)
      # site pages are using these themes.
      # TODO: Implement multiple themes properly.
      themes = %w[light dark]
    else
      mode = color_mode_with_override(current_user)
      themes = []

      themes << color_mode_light_theme(current_user) unless mode == ColorMode::DARK
      themes << color_mode_dark_theme(current_user)  unless mode == ColorMode::LIGHT
    end

    stylesheets = themes.map do |theme_name|
      T.bind(self, BundleHelper)
      stylesheet_bundle("#{theme_name}#{ experimental ? "_experimental" : ""}")
    end
    unloaded_themes = (UserTheme::THEMES - themes)
    unloaded_stylesheets = unloaded_themes.map do |theme_name|
      T.bind(self, BundleHelper)
      stylesheet_bundle("#{theme_name}#{ experimental ? "_experimental" : ""}", lazy: true, tag_options: { "data-color-theme" => theme_name })
    end

    safe_join(stylesheets + unloaded_stylesheets)
  end

  # Returns the current color mode, accounting for controller/action-specific overrides.
  #
  # See ApplicationController#disable_color_modes
  def color_mode_with_override(user)
    ColorMode.color_mode_with_override(user, request)
  end

  sig { params(user: T.nilable(User)).returns(T.any(ColorMode, String)) }
  def color_mode(user)
    cookie_color_mode = T.unsafe(self).request.cookies["preferred_color_mode"] || ColorMode.default
    color_mode_with_override = color_mode_with_override(user)
    return cookie_color_mode if color_mode_with_override.auto?
    color_mode_with_override
  end

  sig { returns T::Boolean }
  def viewer_using_dark_color_mode?
    color_mode(current_user) == ColorMode::DARK
  end

  # Returns the current color mode that a user has set via system settings.
  #
  # The use case for this method is to help determine the correct color mode for Zuora hosted payment pages.
  # They hosted pages use an iframe that we cannot pass parameters to (a Zuora limitation), so we can't use the media query approach
  # that would normally cover this use case. We don't recommend using this method unless it is for a similar technical constraint,
  # as using media queries is a better solution for most use cases.
  def active_color_mode(preferred_color_mode: nil)
    if color_mode_with_override(current_user).auto?
      if preferred_color_mode == ColorMode::DARK && UserTheme.light_themes.include?(current_user&.dark_theme)
        return ColorMode::LIGHT
      end

      if preferred_color_mode == ColorMode::LIGHT && UserTheme.dark_themes.include?(current_user&.light_theme)
        return ColorMode::DARK
      end

      ColorMode::AUTO
    elsif color_mode_with_override(current_user).dark?
      ColorMode::DARK
    else
      ColorMode::LIGHT
    end
  end

  # Get the theme currently active for the user
  # If single mode is set, get the single theme
  # If auto mode is set return the lighttheme
  def active_color_theme(preferred_color_mode: nil)
    if color_mode_with_override(current_user).auto?
      if preferred_color_mode == ColorMode::DARK
        return color_mode_dark_theme(current_user)
      end

      if preferred_color_mode == ColorMode::LIGHT
        return color_mode_light_theme(current_user)
      end

      color_mode_light_theme(current_user)
    elsif color_mode_with_override(current_user).dark?
      color_mode_dark_theme(current_user)
    else
      color_mode_light_theme(current_user)
    end
  end

  def color_mode_light_theme(user)
    # Show an increased-contrast theme:
    # - If the feature flag is enabled (for the logged-out user), and
    # - The cookie value demands it, and
    # - The user is logged-out (since logged-in users select increased-contrast themes by another feature flag)
    if (
      feature_enabled_globally_or_for_visitor?(feature_name: :appearance_settings_logged_out_users) &&
      request&.cookies["increase_contrast_light"] == "enabled" &&
      user.nil?
    )
      UserTheme.from_name("light_high_contrast")
    else
      ColorMode.light_theme_for_user(user, request)
    end
  end

  def color_mode_dark_theme(user)
    # Show an increased-contrast theme:
    # - If the feature flag is enabled (for the logged-out user), and
    # - The cookie value demands it, and
    # - The user is logged-out (since logged-in users select increased-contrast themes by another feature flag)
    if (
      feature_enabled_globally_or_for_visitor?(feature_name: :appearance_settings_logged_out_users) &&
      request&.cookies["increase_contrast_dark"] == "enabled" &&
      user.nil?
    )
      UserTheme.from_name("dark_high_contrast")
    else
      ColorMode.dark_theme_for_user(user, request)
    end
  end

  def color_mode_attributes
    attributes = {
      "data-color-mode": color_mode_with_override(current_user),
      "data-light-theme": color_mode_light_theme(current_user),
      "data-dark-theme": color_mode_dark_theme(current_user)
    }

    tag_attributes(attributes)
  end

  def color_scheme_meta_tag
    if color_mode_with_override(current_user).dark?
      meta_content = "dark light"
    else
      meta_content = "light dark"
    end

    tag(:meta, name: "color-scheme", content: meta_content)
  end

  def color_mode_attributes_checks_logs
    return if ColorMode.disabled?(request)

    attributes = {
      "data-color-mode": "dark",
      "data-dark-theme": active_color_theme.to_s.sub(/^light/, "dark"),
    }

    tag_attributes(attributes)
  end

  # Whether the current controller/action requests all themes.
  def color_modes_all_themes?
    !!request&.env["gh_color_modes_all_themes"]
  end

  # Returns a <picture> tag with the correct image based on the current user's
  # color mode preference.
  #
  # For example:
  #  light_or_dark_picture_tag(
  #    "modules/notifications/inbox-zero.svg",
  #    "modules/notifications/inbox-zero-dark.svg",
  #    class: "py-2",
  #    style: "width: 480px; max-width: 90%; height: auto;",
  #    alt: "Inbox zero"
  #  )
  def light_or_dark_picture_tag(light_path, dark_path, options = {})
    tag.picture do
      if color_mode_with_override(current_user).auto?
        tag.source(
          srcset: image_path(color_mode_dark_theme(current_user).color_mode.dark? ? dark_path : light_path),
          media: "(prefers-color-scheme: dark)"
        ) +
        tag.source(
          srcset: image_path(color_mode_light_theme(current_user).color_mode.light? ? light_path : dark_path),
          media: "(prefers-color-scheme: light), (prefers-color-scheme: no-preference)"
        ) +
        tag.img(src: image_path(light_path), **options)
      elsif color_mode_with_override(current_user).dark?
        tag.img(src: image_path(dark_path), **options)
      else
        tag.img(src: image_path(light_path), **options)
      end
    end
  end

  # Returns a <picture> tag with the correct image based on the current user's
  # color theme preference (light, dark, dimmed, high-contrast, etc.). It takes
  # a map that has a key for each color mode and a value that is image path.
  #
  # For example:
  # mona_map = {
  #   light: "mona-loading.gif",
  #   dark: "mona-loading.gif",
  #   dark_high_contrast: "mona-loading-hc.gif",
  #   dark_dimmed: "mona-loading-dimmed.gif"
  # }
  # color_theme_picture_tag(
  #   mona_map,
  #   class: "py-2",
  #   style: "width: 480px; max-width: 90%; height: auto;",
  #   alt: "Inbox zero"
  # )
  def color_theme_picture_tag(img_path_map, options = {})
    if img_path_map[:light].blank? || img_path_map[:dark].blank?
      raise ArgumentError, "Missing light or dark path. Please provide a map with image paths for at least two keys: :light and :dark"
    end

    light_mode_path = img_path_map[color_mode_light_theme(current_user).to_sym] || img_path_map[UserTheme::DEFAULT_LIGHT.to_sym]
    dark_mode_path = img_path_map[color_mode_dark_theme(current_user).to_sym] || img_path_map[UserTheme::DEFAULT_DARK.to_sym]

    tag.picture do
      if color_mode_with_override(current_user).auto?
        tag.source(
          srcset: image_path(dark_mode_path),
          media: "(prefers-color-scheme: dark)"
        ) +
        tag.source(
          srcset: image_path(light_mode_path),
          media: "(prefers-color-scheme: light), (prefers-color-scheme: no-preference)"
        ) +
        tag.img(src: image_path(light_mode_path), **options)
      elsif color_mode_with_override(current_user).dark?
        tag.img(src: image_path(dark_mode_path), **options)
      else
        tag.img(src: image_path(light_mode_path), **options)
      end
    end
  end
end
