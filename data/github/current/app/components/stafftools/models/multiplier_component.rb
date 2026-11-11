# typed: strict
# frozen_string_literal: true

class Stafftools::Models::MultiplierComponent < ApplicationComponent
  sig { params(multiplier: GitHubModels::Multiplier).void }
  def initialize(multiplier:)
    @multiplier = multiplier
  end

  private

  sig { returns(GitHubModels::Multiplier) }
  attr_reader :multiplier

  sig { returns T.nilable(T::Boolean) }
  def render?
    GitHub.models_enabled? && logged_in?
  end

  sig { returns(String) }
  def action
    multiplier.persisted? ? "Update" : "Create"
  end

  sig { returns(String) }
  def form_url
    multiplier.persisted? ? stafftools_models_multiplier_path(multiplier) : stafftools_models_multipliers_path
  end

  sig { returns(Symbol) }
  def form_method
    multiplier.persisted? ? :put : :post
  end

  sig { returns(T::Array[String]) }
  memoize def existing_models_slugs
    GitHubModels::Model.all.pluck(:slug)
  end
end
