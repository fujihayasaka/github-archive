# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class FeatureFlags < Seeds::Runner
      def self.help
        <<~HELP
        Seed feature flags for local development
        HELP
      end

      def self.run(options = {})
        raise ActiveRecord::RecordInvalid.new if options[:name].blank?

        feature_name = options[:name]
        return if FeatureFlag.vexi.exists_or_raise?(feature_name) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage

        FeatureFlag.vexi_management.disable_feature_flag(feature_name)
      end
    end
  end
end
