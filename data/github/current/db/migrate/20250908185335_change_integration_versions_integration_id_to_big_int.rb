# typed: true
# frozen_string_literal: true

class ChangeIntegrationVersionsIntegrationIdToBigInt < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def up
    change_table :integration_versions, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :integration_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :integration_versions, bulk: true do |t|
      t.change :id, :int, null: false, auto_increment: true
      t.change :integration_id, :int, null: false
    end
  end
end
