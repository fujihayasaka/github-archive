# typed: true
# frozen_string_literal: true

module Copilot
  class BadgeComponent < ApplicationComponent
    extend T::Sig

    STATES = %w(error loading default).freeze
    DEFAULT_STATE = "default"

    sig { params(state: T.any(String, Symbol), unread: T::Boolean).void }
    def initialize(state: DEFAULT_STATE, unread: false)
      @state = fetch_or_fallback(STATES, state.to_s, DEFAULT_STATE)
      @unread = unread
    end

    private

    sig { returns String }
    attr_reader :state

    sig { returns T::Boolean }
    attr_reader :unread

    sig { returns T::Boolean }
    def error?
      state == "error"
    end

    sig { returns T::Boolean }
    def loading?
      state == "loading"
    end
  end
end
