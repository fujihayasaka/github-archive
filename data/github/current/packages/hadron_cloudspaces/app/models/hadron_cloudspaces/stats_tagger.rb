# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module HadronCloudspaces
  class StatsTagger < Codespaces::StatsTagger
    include CloudEnvironments::IStatsTagger
    # This should probably be the base and then extended for different experience types
    def initialize(**kwargs)
      super(**kwargs, is_task_cloud_environment: true)
    end
  end
end
