# typed: strict
# frozen_string_literal: true

require_relative "no_op_client"

module AzureEXP
  module V2
    module Experiments
      # Configures the AzureEXP::V2::Experiments module for the current environment.
      #
      # In production, wires up the real TAS client with Faraday + Resilient.
      # In dev/test/Codespaces, uses NoOpClient (all fetches return defaults).
      #
      # Configuration is lazy-loaded on first access to
      # AzureEXP::V2::Experiments.config.
      class Config
        extend T::Helpers

        sig { returns(T.any(AzureEXP::V2::Experiments::Client, AzureEXP::V2::Experiments::NoOpClient)) }
        attr_reader :client

        sig { void }
        def initialize
          @client = T.let(build_client, T.any(AzureEXP::V2::Experiments::Client, AzureEXP::V2::Experiments::NoOpClient))
        end

        private

        sig { returns(T.any(AzureEXP::V2::Experiments::Client, AzureEXP::V2::Experiments::NoOpClient)) }
        def build_client
          if use_no_op?
            AzureEXP::V2::Experiments::NoOpClient.new
          else
            require_relative "client"
            AzureEXP::V2::Experiments::Client.new
          end
        end

        sig { returns(T::Boolean) }
        def use_no_op?
          # No-op in test, development, and CI by default.
          # No-op on Enterprise (GHES) and Proxima (multi-tenant): TAS isn't
          # available there, so all fetches return caller defaults.
          # Production and review labs use the real client.
          Rails.env.test? ||
            Rails.env.development? ||
            ENV["GITHUB_CI"].present? ||
            GitHub.single_or_multi_tenant_enterprise?
        end
      end
    end
  end
end
