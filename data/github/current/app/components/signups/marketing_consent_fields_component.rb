# typed: true
# frozen_string_literal: true

module Signups
  class MarketingConsentFieldsComponent < ApplicationComponent
    sig { returns(T::Boolean) }
    def render?
      helpers.signups_preferences_enabled?
    end
  end
end
