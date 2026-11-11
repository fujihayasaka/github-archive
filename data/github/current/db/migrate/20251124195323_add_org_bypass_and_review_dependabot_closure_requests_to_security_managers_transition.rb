# typed: true
# frozen_string_literal: true

require "github/transitions/20251124195323_add_org_bypass_and_review_dependabot_closure_requests_to_security_managers"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class AddOrgBypassAndReviewDependabotClosureRequestsToSecurityManagersTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddOrgBypassAndReviewDependabotClosureRequestsToSecurityManagers.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
