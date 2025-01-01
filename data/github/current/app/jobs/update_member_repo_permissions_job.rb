# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateMemberRepoPermissionsJob < ApplicationJob
  queue_as :update_member_repo_permissions

  def perform(member, action:, repo:, actor:)
    with_write { repo.update_member(member, action: action.to_sym, actor: actor) }
    raise RuntimeError.new if repo.errors.any?
  end
end
