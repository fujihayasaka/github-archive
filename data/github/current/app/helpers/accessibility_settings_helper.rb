# typed: strict
# frozen_string_literal: true

module AccessibilitySettingsHelper
  extend T::Helpers
  include TagAttributeHelper

  # Public: Outputs the accessibility settings for the current user in "data-"
  # tag format, so it can be made available at the root element for client code.
  sig { returns(String) }
  def accessibility_attributes
    if current_user&.feature_flag_enabled?(:magic_shell_caching, default: false)
      link_underlines = magic_shell.accessibility_link_underlines_enabled?
    else
      link_underlines = current_user&.settings&.get(:link_underlines)
    end
    link_underlines = true if link_underlines.nil?

    animated_images = current_user&.settings&.get(:animated_images)
    animated_images = "system" if animated_images.nil?

    attributes = {
      "data-a11y-animated-images": animated_images,
      "data-a11y-link-underlines": link_underlines
    }

    tag_attributes(attributes)
  end

  abstract!

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end

  sig { abstract.returns(MagicShell) }
  def magic_shell; end
end
