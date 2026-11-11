# typed: true
# frozen_string_literal: true

require "github/transitions/20220921003202_add_manage_security_products_settings_fgp"

class AddManageSecurityProductsSettingsFgpTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AddManageSecurityProductsSettingsFgp.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
