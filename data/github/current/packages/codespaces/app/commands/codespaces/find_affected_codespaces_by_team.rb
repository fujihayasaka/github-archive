# typed: true
# frozen_string_literal: true

module Codespaces
  class FindAffectedCodespacesByTeam < Command
    attr_reader :deletion_reason

    def initialize(team_id:, deletion_reason: nil)
      @team_id = team_id
      @deletion_reason = deletion_reason
    end

    def perform
      # load up all of the codespaces that this team owns
      team = Team.find(@team_id)
      member_ids = team.members.pluck(:id)
      T.must(team.organization).repositories.in_batches do |repository_batch|
        repository_ids = repository_batch.pluck(:id).uniq
        Codespace.where(repository: repository_ids, owner_id: member_ids).in_batches do |codespace_batch|
          CodespacesProcessSystemEventJob.perform_later(codespaces: codespace_batch.sort, deletion_reason: deletion_reason)
        end
      end
    end
  end
end
