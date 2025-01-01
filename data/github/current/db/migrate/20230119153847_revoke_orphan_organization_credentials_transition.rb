# typed: true
# frozen_string_literal: true

require "github/transitions/20230119153847_revoke_orphan_organization_credentials"

class RevokeOrphanOrganizationCredentialsTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::RevokeOrphanOrganizationCredentials.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
