# typed: true
class AddNoteToIgnoredUsers < ActiveRecord::Migration[7.1]
  def change
    change_table :ignored_users, bulk: true do |t|
      t.column :note, :string, limit: 100, default: nil

      # Converting columns to bigint due to GitHub/ExistingIdColumnsMustBeBigint linter
      t.change :user_id, :bigint, unsigned: true
      t.change :ignored_id, :bigint, unsigned: true
      t.change :id, :bigint, unsigned: true
      t.change :blocked_from_content_id, :bigint, unsigned: true
    end
  end
end
