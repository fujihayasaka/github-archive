# typed: strict
# frozen_string_literal: true

class Businesses::Actions::Policies::RepoSelfHostedRunnerComponent < ApplicationComponent

  sig { params(entity: Business, action: String).void }
  def initialize(entity:, action:)
    @entity = entity
    @action = action
  end

  sig { returns(T::Boolean) }
  def render?
    true
  end
end
