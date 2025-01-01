# typed: true
# frozen_string_literal: true

class Codespaces::DevContainer::AddStaticOptionsComponent < ApplicationComponent
  attr_reader :feature

  def initialize(feature:)
    @feature = feature
  end
end
