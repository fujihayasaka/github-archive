# typed: true
# frozen_string_literal: true

class Stafftools::Models::UserInfoComponent < ApplicationComponent
  sig { params(user: User).void }
  def initialize(user:)
    @user = user
  end

  private

  sig { returns User }
  attr_reader :user

  sig { returns T::Boolean }
  def render?
    return false unless GitHub.models_enabled? && logged_in?
    access_result = with_database_error_fallback(fallback: nil) { self.access_result }
    !access_result.nil?
  end

  sig { returns GitHubModels::PlaygroundAccessResult }
  memoize def access_result
    GitHubModels::PlaygroundAccessResult.for(user)
  end

  sig { returns T::Boolean }
  def has_models_access?
    access_result.accessible?
  end

  sig { returns T.nilable(String) }
  def access_reason
    reason = access_result.reason
    return unless reason
    reason.to_s.humanize
  end
end
