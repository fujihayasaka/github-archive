# typed: true
# frozen_string_literal: true

class Copilot::Chat::AutocompleteController < Copilot::Chat::AbstractChatController
  before_action :ensure_feature_enabled

  private

  def ensure_feature_enabled
    return if current_user&.feature_enabled?(:copilot_ui_refs)
    render_404
  end
end
