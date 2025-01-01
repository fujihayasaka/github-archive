# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::TierSuggestions::HeaderComponent < ApplicationComponent
  def initialize(sponsorable:)
    @sponsorable = sponsorable
  end

  private

  attr_reader :sponsorable

  def render?
    sponsorable.present?
  end
end
