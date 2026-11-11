# typed: true
# frozen_string_literal: true

class UIContextController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:show]

  def show
    render json: {
      prefersAbsoluteTime: prefers_absolute_time?,
      copilotApiOverrideUrl: view_context.copilot_api_override_url_with_fallback(current_user),
      keyboardShortcutsPreference: keyboard_shortcuts_preference,
      animatedImages: animated_images,
      linkUnderlines: link_underlines,
    }
  end

  private

  def prefers_absolute_time?
    user = current_user
    return false unless user&.feature_flag_enabled?(:respect_absolute_time_preference, default: false)

    user.settings&.get(:relative_time_preference) == "absolute"
  end

  def keyboard_shortcuts_preference
    current_user&.settings&.get(:keyboard_shortcuts_preference)
  end

  def animated_images
    value = current_user&.settings&.get(:animated_images)
    value.nil? ? "system" : value
  end

  def link_underlines
    value = current_user&.settings&.get(:link_underlines)
    value.nil? ? true : value
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end
end
