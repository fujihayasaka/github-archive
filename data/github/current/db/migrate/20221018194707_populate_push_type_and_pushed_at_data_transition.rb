# typed: true
# frozen_string_literal: true

require "github/transitions/20221018194707_populate_push_type_and_pushed_at_data"

class PopulatePushTypeAndPushedAtDataTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::PopulatePushTypeAndPushedAtData.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
