# typed: strict
# frozen_string_literal: true

module AppearanceSettingsHelper
  extend T::Helpers

  include FeatureFlagHelper
  include TagAttributeHelper

  # Public: Output the relative time display preference for current user
  sig { returns(String) }
  def relative_time_display_attributes
    unless current_user&.feature_flag_enabled?(:respect_absolute_time_preference, default: false)
      return ""
    end

    if current_user&.settings&.get(:relative_time_preference) == "absolute"
      attributes = { "data-prefers-absolute-time" => "true" }
      return tag_attributes(attributes)
    end
    ""
  end

  abstract!

  sig { abstract.returns(T.nilable(::User)) }
  def current_user; end
end
