# typed: true
# frozen_string_literal: true

module SecretScanning
  module CustomPatterns
    module DryRun
      class RepoRowComponent < ApplicationComponent
        attr_reader :repository, :owner, :update_selected_repositories_path

        include SecretScanningCustomPatternsHelper

        def initialize(
          repository:,
          owner:,
          update_selected_repositories_path:
        )
          @repository = repository
          @owner = owner
          @update_selected_repositories_path = update_selected_repositories_path
        end
      end
    end
  end
end
