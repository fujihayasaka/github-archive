# typed: true
# frozen_string_literal: true

class Settings::AppearancePreferences::ViewerSettingsController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,

  def show
    # Return 404 if user is not logged in
    return head :not_found unless logged_in?

    # Extract viewer settings based on the user's preferences
    settings = {
      emojiTone: current_user&.profile_settings&.preferred_emoji_skin_tone || 0,
      pasteUrlsAsPlainText: current_user&.paste_url_link_as_plain_text? || false,
      useMonospaceFont: current_user&.use_fixed_width_font? || false
    }

    render json: settings
  end

  private

  def resource_for_conditional_access
    # cap_bypass: this is safe when there is no logged-in user
    return :no_resource_for_conditional_access unless logged_in? # rubocop:todo GitHub/SpecifyResourceForConditionalAccess
    current_user
  end
end
