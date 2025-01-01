# typed: false
# frozen_string_literal: true

require "newsies/options"

module Newsies
  # Internal: Used for the ThreadSubscriptionManager#subscribe method.
  ThreadSubscribeOptions = Options.new(:reason, :force) do
    def self.from_unknown(value)
      fill(reason: value.to_s)
    end

    def reason
      s = self[:reason].to_s
      s.empty? ? nil : s
    end

    alias force? force
  end
end
