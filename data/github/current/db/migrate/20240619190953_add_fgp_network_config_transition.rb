# typed: true
# frozen_string_literal: true

require "github/transitions/20240619190953_add_fgp_network_config"

class AddFgpNetworkConfigTransition < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Iam)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddFgpNetworkConfig.new(arguments)
    transition.run
  end

  def self.down
  end
end
