# typed: true
# frozen_string_literal: true

class ExpandCodespacesPrebuildsOidField < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def up
    change_table :codespace_prebuild_templates, bulk: true do |t|
      t.change :oid, :string, limit: 64, null: false
    end
  end

  def down
    change_table :codespace_prebuild_templates, bulk: true do |t|
      t.change :oid, :string, limit: 40, null: false
    end
  end
end
