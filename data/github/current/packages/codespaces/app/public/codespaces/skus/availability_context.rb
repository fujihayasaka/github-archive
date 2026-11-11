# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module Skus
    # These objects wrap a Codespaces::Skus::Sku to surface richer information
    # about their availability in the dotcom UI.
    class AvailabilityContext
      attr_accessor :sku, :enabled, :reason, :default
      BELOW_DEVCONTAINER_REQUIREMENTS = "Below dev container requirements"
      DOES_NOT_MEET_MACHINE_POLICY = "Disabled by organization or enterprise policy"

      def initialize(sku:, enabled:, reason: nil)
        @sku = sku # The machine type's corresponding Codespaces::Skus::Sku
        @enabled = enabled # Whether this machine type can be selected
        @reason = reason # Why this machine type cannot be selected, if applicable
        @default = false # Whether this machine type is selected by default
      end

      def self.for_skus(skus, dev_container: nil, policy_allowed_skus: nil, preferred_default: nil)
        sorted_skus = Codespaces::Skus.resource_ascending_skus(skus)
        default_set = T.let(false, T::Boolean)
        # Not likely with our current offerings, but there's the possiblility a
        # middle-ranked SKU is below spec, despite an earlier one being acceptable.
        availability_contexts = sorted_skus.map do |sku|
          availability_context = new(sku: sku, enabled: true)
          case
          when !policy_allowed_skus.nil? && !policy_allowed_skus.include?(sku)
            availability_context.enabled = false
            availability_context.reason = AvailabilityContext::DOES_NOT_MEET_MACHINE_POLICY
          when !sku.allowed_for_devcontainer?(dev_container)
            availability_context.enabled = false
            availability_context.reason = AvailabilityContext::BELOW_DEVCONTAINER_REQUIREMENTS
          when !default_set
            availability_context.default = true
            default_set = true
          end
          availability_context
        end

        if default = availability_contexts.find { |ac| ac.sku.name == preferred_default&.to_sym && ac.enabled }
          availability_contexts.map do |ac|
            ac.default = ac.sku.name == preferred_default.to_sym
            ac
          end
        else
          availability_contexts
        end
      end
    end
  end
end
