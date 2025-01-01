# typed: true
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    class StatsTagger < Codespaces::StatsTagger
      include CloudEnvironments::IStatsTagger
      # This should probably be the base and then extended for different experience types
      def initialize(**kwargs)
        super(**kwargs, is_workbench_cloud_environment: true)
      end
    end
  end
end
