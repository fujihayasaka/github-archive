# typed: true
# frozen_string_literal: true

class Codespaces::CreateConcurrencyErrorComponent < ApplicationComponent
  attr_reader :link_to_index

  def initialize(link_to_index: true)
    @link_to_index = link_to_index
  end
end
