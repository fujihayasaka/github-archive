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
        return if FlipperFeature.find_by(name: options[:name])

        GitHub.flipper[options[:name]].disable
        ::FeatureFlag.vexi_test_adapter.disable(options[:name])
        FlipperFeature.find_by(name: options[:name])
      end
    end
  end
end
