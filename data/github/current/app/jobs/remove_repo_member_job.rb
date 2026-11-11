# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RemoveRepoMemberJob < ApplicationJob
  queue_as :remove_repo_member

  retry_on_dirty_exit

  def perform(member, remover:, repo:)
    with_write { repo.remove_member(member, remover) }
  end
end
