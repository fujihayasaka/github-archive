# typed: true
# frozen_string_literal: true

require "github/transitions/20230210090634_delete_org_discussion_configs_without_repo"

class DeleteOrgDiscussionConfigsWithoutRepoTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !GitHub::AppEnvironment.development?
    transition = GitHub::Transitions::DeleteOrgDiscussionConfigsWithoutRepo.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
