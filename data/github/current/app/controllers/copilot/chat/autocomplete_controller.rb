# typed: true
# frozen_string_literal: true

class Copilot::Chat::AutocompleteController < Copilot::Chat::AbstractChatController
  before_action :ensure_feature_enabled

  RESULT_LIMIT = 5

  private

  def query_value
    params[:q].to_s.strip.downcase || ""
  end

  def ensure_feature_enabled
    return if current_user&.feature_enabled?(:copilot_chat_autocomplete)
    render_404
  end
end
