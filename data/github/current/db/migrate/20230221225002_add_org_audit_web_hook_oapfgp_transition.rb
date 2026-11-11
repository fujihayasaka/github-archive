# typed: true
# frozen_string_literal: true

require "github/transitions/20230221225002_add_org_audit_web_hook_oapfgp"

class AddOrgAuditWebHookOapfgpTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !GitHub::AppEnvironment.development?
    transition = GitHub::Transitions::AddOrgAuditWebHookOapfgp.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
