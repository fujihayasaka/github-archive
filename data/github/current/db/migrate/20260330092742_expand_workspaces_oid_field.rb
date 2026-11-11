# typed: true
# frozen_string_literal: true

class ExpandWorkspacesOidField < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def up
    change_table :workspaces, bulk: true do |t|
      t.change :oid, :string, limit: 64, null: false
    end
  end

  def down
    change_table :workspaces, bulk: true do |t|
      t.change :oid, :char, limit: 40, null: false
    end
  end
end
