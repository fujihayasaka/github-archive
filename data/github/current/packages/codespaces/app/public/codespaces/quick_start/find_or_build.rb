# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module QuickStart
    class FindOrBuild < Command
      attr_reader :owner, :repository, :template_repository, :ref, :pull_request, :devcontainer_path
      def initialize(
        owner:,
        repository:,
        template_repository: nil,
        ref: nil,
        pull_request: nil,
        devcontainer_path: nil
      )
        @owner = owner
        @repository = repository
        @template_repository = template_repository
        @ref = ref
        @pull_request = pull_request
        @devcontainer_path = devcontainer_path
      end

      def perform
        resumable_codespace || new_codespace
      end

      private

      def resumable_codespace
        Codespaces::QuickStart::ResumeFilter.new(
          codespaces: query.all_accessible_codespaces,
          repository:,
          ref:,
          pull_request:,
          devcontainer_path:,
        ).resumable_codespace
      end

      def new_codespace
        args = {
          owner:,
          repository:,
          template_repository:,
          devcontainer_path:
        }
        if pull_request.present?
          args[:pull_request] = pull_request
          # We expect to be created on the PR's head repository
          args[:repository] = pull_request.head_repository
        else
          args[:ref] = creatable_ref
        end
        Codespace.new(**args)
      end

      def creatable_ref
        # If we're creating a new codespace we need the ref to exist.
        # We cannot use this for filtering since it is possible for the ref to _only_ exist in an existing codespace.
        if repository.refs.find(ref)
          ref
        else
          repository.default_branch
        end
      end

      def query
        @query ||= Codespaces::Query.new(current_user: owner)
      end
    end
  end
end
