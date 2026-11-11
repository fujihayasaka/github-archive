# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class GlobalNavReactCodespaces < Seeds::Runner
      def self.help
        <<~HELP
        Enables the global_nav_react feature flag for Codespaces development.

        This ensures that developers working in Codespaces see the production React-based
        global navigation instead of the legacy Rails-based navigation.
        HELP
      end

      def self.run(options = {})
        puts "Enabling global_nav_react feature flag..."
        Seeds::Objects::FeatureFlag.enable(feature_flag: "global_nav_react")
        puts "Successfully enabled global_nav_react feature flag"
      end
    end
  end
end
