# typed: true
require "github/transitions/20220728043218_add_view_security_managers_policy_to_security_manager"

class AddViewSecurityManagersPolicyToSecurityManager < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AddViewSecurityManagersPolicyToSecurityManager.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
