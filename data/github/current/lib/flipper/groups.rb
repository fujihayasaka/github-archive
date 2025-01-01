# typed: strict
# frozen_string_literal: true

# When modifying existing groups, or adding new ones, please update the documentation on TheHub
# with the list of groups and their descriptions.
#
# See https://thehub.github.com/engineering/development-and-ops/dotcom/features/feature-flags/groups/

require "feature_flags_common/custom_gates"

module Flipper
  class Groups
    sig { returns(T.untyped) }
    def self.register_groups
      # IMPORTANT!: Do not add new group gates to this file. We are in the process of migrating over to Vexi from Flipper
      # To add a new group gate, please see the documentation on The Hub
      # https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/groups
      FeatureFlagsCommon::CustomGates::CUSTOM_GATES.each do |custom_gate, gate_proc|
        ::Flipper.register(custom_gate) do |actor, context|
          GitHub.dogstats.distribution_time("feature_flags.groups.check.latency", tags: ["group:#{custom_gate}", "actor_type:#{actor.class.name}"]) do
            feature_name = nil
            if context.respond_to?(:feature_name)
              feature_name = context.feature_name
            end
            gate_proc.call(actor, feature_name.to_s)
          end
        end
      end
    end

    sig { void }
    def self.unregister_groups
      ::Flipper.unregister_groups
    end

    sig { returns(Flipper::Types::Group) }
    def self.preview_features
      ::Flipper.group(:preview_features)
    end
  end
end
