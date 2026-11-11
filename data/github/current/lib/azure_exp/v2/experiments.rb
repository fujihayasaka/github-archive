# typed: true
# frozen_string_literal: true

require_relative "experiments/config"
require_relative "experiments/context"
require_relative "experiments/in_memory_cache"
require_relative "experiments/assignment_result"
require_relative "experiments/participant"
require_relative "experiments/middleware/memoizer"
require_relative "experiments/test_helpers"

module AzureEXP
  module V2
    module Experiments
      extend T::Helpers

      # Request-scoped storage via ActiveSupport::CurrentAttributes.
      # Automatically reset between requests by Rails.
      class Current < ActiveSupport::CurrentAttributes
        attribute :context
      end

      # Returns the request-scoped treatment context for the current request.
      # Lazily initialized on first access. Accumulate userParams via `add`,
      # then read treatment values via `fetch`.
      #
      #   AzureEXP::V2::Experiments.current.add(AzureEXP::V2::Experiments::Participant::UNIT_USER, user.id.to_s)
      #   AzureEXP::V2::Experiments.current.fetch("/copilot/header_v2", "control")
      #
      sig { returns(AzureEXP::V2::Experiments::Context) }
      def self.current
        # ActiveSupport::CurrentAttributes defines its `attribute` accessors
        # (here, `context`) via runtime metaprogramming, which Sorbet cannot
        # see, so T.unsafe is required to call them. Keep the unsafe surface to
        # this single line and the assignment in the test helpers.
        T.unsafe(Current).context ||= Context.new(config.client)
      end

      sig { returns(AzureEXP::V2::Experiments::Config) }
      def self.config
        @config ||= T.let(AzureEXP::V2::Experiments::Config.new, T.nilable(AzureEXP::V2::Experiments::Config))
      end

      sig { void }
      def self.reset_config!
        @config = T.let(nil, T.nilable(AzureEXP::V2::Experiments::Config))
      end
    end
  end
end
