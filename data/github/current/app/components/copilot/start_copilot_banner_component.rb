# typed: strict
# frozen_string_literal: true

module Copilot
  class StartCopilotBannerComponent < ApplicationComponent
    extend T::Sig

    sig { returns(Copilot::User) }
    attr_reader :copilot_user

    sig { params(copilot_user: Copilot::User).void }
    def initialize(copilot_user)
      @copilot_user = T.let(copilot_user, Copilot::User)
    end

    sig { returns(T::Boolean) }
    memoize def eligible_for_trial
      copilot_user.eligible_for_trial?
    end

    private

    sig { returns(T::Boolean) }
    def render?
      return false unless GitHub.billing_enabled?
      return false if copilot_user.is_enterprise_managed?

      instrument_cta_viewed
      true
    end

    sig { returns(String) }
    def hydro_tracking_label
      cta_label = eligible_for_trial ? "start_a_free_trial" : "buy_copilot"

      "user:#{current_user&.id};ref_cta:#{cta_label}"
    end

    sig { void }
    def instrument_cta_viewed
      GlobalInstrumenter.instrument("analytics.event",
        category: "copilot_settings",
        action: "copilot_for_individual_banner_viewed",
        label: hydro_tracking_label,
      )
    end
  end
end
