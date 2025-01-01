# typed: true
# frozen_string_literal: true

class UpdatePagesReplicas < ActiveRecord::Migration[4.2]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    change_table :pages_replicas, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false
      t.change :page_id, :bigint, unsigned: true, null: false
      t.change :pages_deployment_id, :bigint, unsigned: true, null: true
    end
  end

  def down
    change_table :pages_replicas, bulk: true do |t|
      t.change :id, :int, unsigned: true, null: false
      t.change :page_id, :int, unsigned: true, null: false
      t.change :pages_deployment_id, :int, unsigned: true, null: true
    end
  end
end
