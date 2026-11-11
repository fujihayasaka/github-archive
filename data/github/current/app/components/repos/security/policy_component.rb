# typed: true
# frozen_string_literal: true

module Repos
  module Security
    class PolicyComponent < ApplicationComponent
      attr_reader :repository, :show_blankslate_border, :system_arguments

      def initialize(repository:, show_blankslate_border: false, **system_arguments)
        @repository = repository
        @show_blankslate_border = show_blankslate_border
        @system_arguments = system_arguments
      end

      memoize def blob_view
        helpers.create_view_model(Blob::ShowView, {
          repo: security_policy.repository,
          tree_name: security_policy.default_branch,
          blob: security_policy.file,
        })
      end

      memoize def new_file_view
        helpers.create_view_model(Files::NewFileActionView, {
          repo: repository,
          tree_name: repository.default_branch,
        })
      end

      def non_collaborator?
        !AdvisoryDB.collaborator?(repository: repository, user: current_user)
      end

      memoize def security_policy
        repository.security_policy
      end
    end
  end
end
