# typed: true
# frozen_string_literal: true

class Copilot::Chat::AutocompleteController < Copilot::Chat::AbstractChatController
  RESULT_LIMIT = 5

  private

  def query_value
    params[:q].to_s.strip.downcase || ""
  end
end
