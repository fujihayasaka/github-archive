# typed: true
# frozen_string_literal: true

class AddSubjectTypeAndIdIndexToRestorableMemberships < ActiveRecord::Migration[8.1]
  use_connection_class(ApplicationRecord::Domain::Restorables)

  def up
    change_table(:restorable_memberships, bulk: true) do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :restorable_id, :bigint, unsigned: true, null: false
      t.change :subject_id, :bigint, unsigned: true, null: false

      t.index [:subject_id, :subject_type], name: "index_restorable_memberships_on_subject_type_and_id"
    end
  end

  def down
    change_table(:restorable_memberships, bulk: true) do |t|
      t.remove_index name: "index_restorable_memberships_on_subject_type_and_id"

      t.change :subject_id, :integer, unsigned: false, null: false
      t.change :restorable_id, :integer, unsigned: false, null: false
      t.change :id, :integer, unsigned: false, null: false, auto_increment: true
    end
  end
end
