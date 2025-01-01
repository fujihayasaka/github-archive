# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module QuickStart
    class ResumeFilter
      attr_reader :codespaces, :repository, :ref, :pull_request, :devcontainer_path

      def initialize(
          codespaces:,
          repository:,
          ref: nil,
          pull_request: nil,
          devcontainer_path: nil
        )
        @codespaces = codespaces
        @repository = repository
        @ref = ref
        @pull_request = pull_request
        @devcontainer_path = devcontainer_path
      end

      def resumable_codespace
        return unless repository.present?
        return unless codespaces.present?

        filtered_codespaces = codespaces

        filters = []
        if pull_request.present?
          filters << proc { |codespace| codespace.pull_request == pull_request }
          if repository.present?
            filters << proc { |codespace| codespace.repository == pull_request.head_repository || codespace.repository == repository }
          else
            filters << proc { |codespace| codespace.repository == pull_request.head_repository }
          end
        elsif repository.present?
          filters << proc { |codespace| codespace.repository == repository }
        end
        filters << proc { |codespace| codespace.display_branch == ref } if ref
        filters << proc { |codespace| codespace.devcontainer_path == devcontainer_path } if devcontainer_path.present?
        filters.each do |filter|
          filtered_codespaces = filtered_codespaces.filter(&filter)
        end
        filtered_codespaces.sort_by(&:last_used_at).last
      end
    end
  end
end
