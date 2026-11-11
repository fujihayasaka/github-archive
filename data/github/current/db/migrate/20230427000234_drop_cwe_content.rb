# typed: true
# frozen_string_literal: true

class DropCWEContent < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Notify)

  def change
    return if !GitHub.enterprise? && !Rails.env.development?
    execute "TRUNCATE TABLE cwes"
  end
end
