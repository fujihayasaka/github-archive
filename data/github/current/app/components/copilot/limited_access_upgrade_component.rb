# typed: strict
# frozen_string_literal: true

module Copilot
  class LimitedAccessUpgradeComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    sig { returns(Copilot::User) }
    attr_reader :copilot_user

    sig { params(copilot_user: Copilot::User).void }
    def initialize(copilot_user)
      @copilot_user = T.let(copilot_user, Copilot::User)
    end

    sig { returns(T::Boolean) }
    def render?
      return true if copilot_user.has_limited_access?
      false
    end

  end
end
