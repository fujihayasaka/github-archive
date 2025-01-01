# typed: true
# frozen_string_literal: true

class Organizations::Settings::SecurityManagerSuggestionsComponent < ApplicationComponent
  def initialize(suggestions:, organization:)
    @suggestions = suggestions
    @organization = organization
  end
end
