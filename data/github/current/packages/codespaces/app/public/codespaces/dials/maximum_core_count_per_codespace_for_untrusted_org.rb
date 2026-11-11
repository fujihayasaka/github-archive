# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module Dials
    class MaximumCoreCountPerCodespaceForUntrustedOrg < Codespaces::Dial

      validates :value,
                inclusion: { in: Codespaces::Skus.valid_sku_cpus.map(&:to_s), message: "must be a valid CPU core count" }

      sig { override.returns(String) }
      def key
        "codespaces_maximum_core_count_per_codespace_for_untrusted_org"
      end

      sig { override.returns(String) }
      def default_value
        "16"
      end

      sig { override.returns(String) }
      def description
        "This value restricts Codespace SKUs available to UNTRUSTED organizations by CPU core count. For example,
        when this dial's value is set to 16, only the SKUs with a core count less than or equal to 16 will be
        available to UNTRUSTED organizations."
      end
    end
  end
end
