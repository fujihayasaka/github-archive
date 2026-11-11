# typed: true
# frozen_string_literal: true

class Stafftools::CopilotSpaces::UserBlockComponent < ApplicationComponent
  sig { params(user: User).void }
  def initialize(user:)
    @user = user
  end

  sig { returns User }
  attr_reader :user

  sig { returns(T::Boolean) }
  def spaces_blocked?
    FeatureFlag.vexi.enabled?(:copilot_spaces_user_blocked, user, default: false)
  end

  private

  sig { returns T.nilable(T::Boolean) }
  def render?
    return false unless GitHub.copilot_enabled? && logged_in?
    true
  end
end
