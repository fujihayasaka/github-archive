# typed: true
# frozen_string_literal: true

module WorkspaceEditor
  module Cloudspaces
    class StatsTagger < Codespaces::StatsTagger
      include CloudEnvironments::IStatsTagger
      # This should probably be the base and then extended for different experience types
      def initialize(**kwargs)
        super(**kwargs, is_workspace_editor_cloud_environment: true)
      end
    end
  end
end
