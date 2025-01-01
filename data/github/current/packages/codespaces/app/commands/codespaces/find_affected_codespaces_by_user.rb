# typed: true
# frozen_string_literal: true

module Codespaces
  class FindAffectedCodespacesByUser < Command
    attr_reader :deletion_reason

    def initialize(user_id:, deletion_reason: nil)
      @user_id = user_id
      @deletion_reason = deletion_reason
    end

    def perform
      # load up all of the codespaces that this user owns
      codespaces = Codespace.where(owner: @user_id)
      # send that list to CodespacesProcessSystemEventJob
      CodespacesProcessSystemEventJob.perform_later(codespaces: codespaces.to_a, deletion_reason: deletion_reason)
    end
  end
end
