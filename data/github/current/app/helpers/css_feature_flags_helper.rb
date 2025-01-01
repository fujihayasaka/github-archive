# typed: strict
# frozen_string_literal: true

module CssFeatureFlagsHelper
  extend T::Helpers

  include TagAttributeHelper
  include FeatureFlagHelper

  # Public: Outputs the accessibility settings for the current user in "data-"
  # tag format, so it can be made available at the root element for client code.
  sig { returns(String) }
  def css_feature_flag_attribute
    return "" unless css_feature_flags.present?
    flags = css_feature_flags.join(" ")
    return "" unless flags.present?

    tag_attributes({
      "data-css-features": flags,
    })
  end
end
