# typed: strict
# frozen_string_literal: true

module Discussions
  module Transfers
    module CandidateRepositories
      class RepositoryComponent < ApplicationComponent
        DESCRIPTION_MAX_LENGTH = 150

        sig { params(repository: Repository).void }
        def initialize(repository:)
          @repository = T.let(repository, Repository)
        end

        private

        sig { returns(Repository) }
        attr_reader :repository

        sig { returns(String) }
        def description
          repository.short_description_html(limit: DESCRIPTION_MAX_LENGTH)
        end
      end
    end
  end
end
