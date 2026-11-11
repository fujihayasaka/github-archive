# typed: strict
# frozen_string_literal: true

module Copilot
  class HideCopilotComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    sig { returns(Copilot::User) }
    attr_reader :copilot_user

    sig { params(copilot_user: Copilot::User).void }
    def initialize(copilot_user)
      @copilot_user = T.let(copilot_user, Copilot::User)
    end

    sig { returns(String) }
    memoize def show_copilot_text
      show_copilot_enabled? ? "Enabled" : "Disabled"
    end

    sig { returns(T::Boolean) }
    memoize def show_copilot_enabled?
      @copilot_user.show_copilot_enabled?
    end

    sig { returns(T::Boolean) }
    def render?
      return false if copilot_user.is_enterprise_managed?
      return true if !(copilot_user.has_copilot_access? || copilot_user.has_cfb_access?)
      return true if copilot_user.has_limited_access?
      false
    end
  end
end
