# typed: true
# frozen_string_literal: true

class GitHubModels::Businesses::CustomModelsComponent < ApplicationComponent
  sig { params(business: Business).void }
  def initialize(business:)
    @business = business
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless GitHub.models_enabled?
    true
  end

  attr_reader :business
end
