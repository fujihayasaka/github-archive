# typed: true
# frozen_string_literal: true

module Codespaces
  class FindAffectedCodespacesByRepository < Command
    attr_reader :deletion_reason

    def initialize(repository_id:, deletion_reason:)
      @repository_id = repository_id
      @deletion_reason = deletion_reason
    end

    def perform
      # this event is called in app/models/repository/removal_dependency.rb#archive method
      # there is a possibility that the repository has been deleted given that archiving
      # is idempotent so we want to check whether the repository exists before processing
      repository = Repository.find_by(id: @repository_id)

      # also wanna check if the repository owner is in the feature flag
      return unless repository

      # load up all of the codespaces potentially affected
      codespaces = Codespace.where(repository: @repository_id)
      # send that list to CodespacesProcessSystemEventJob
      codespaces.in_batches do |codespace_batch|
        CodespacesProcessSystemEventJob.perform_later(codespaces: codespace_batch.to_a, deletion_reason: deletion_reason)
      end
    end
  end
end
