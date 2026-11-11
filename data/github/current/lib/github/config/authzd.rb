# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Authzd
      extend T::Helpers
      requires_ancestor { GitHub::Config }

      # Setting to determine if authzd CAP is available
      # If available, authzd CAP will be used for supported cases
      # If unavailable, monolith CAP will be used for all CAP checks
      #
      # This is true outside of GHES
      # In GHES, this defaults to false and can be enabled with:
      # ghe-config app.github.authzd-cap-available 1
      def authzd_cap_available?
        return true unless single_tenant_enterprise?
        return @authzd_cap_available if defined?(@authzd_cap_available)
        @authzd_cap_available = false
      end
      attr_writer :authzd_cap_available

      # Setting to determine if rate authzd cap experiment will run in GHES
      #
      # This is for GHES only
      # It defaults to 0 and can be set between 0..100 with
      # ghe-config app.github.authzd-cap-ghes-experiment-percent 42
      def authzd_cap_ghes_experiment_percent
        return 0.0 unless single_tenant_enterprise?
        return @authzd_cap_experiment_percent.to_f if defined?(@authzd_cap_experiment_percent)
        @authzd_cap_experiment_percent = 0.0
      end
      attr_writer :authzd_cap_experiment_percent
    end
  end

  extend Config::Authzd
end
