# rubocop:disable GitHub/SpecifyDefaultCharsetAndCollation
# rubocop:disable GitHub/ReferencingColumnsMustBeBigint
# rubocop:disable GitHub/UseBigintUnsignedPrimaryKeys
class CreateSavedNotificationEntriesSeq < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::VT)

  def change
    create_table :saved_notification_entries_seq, comment: "vitess_sequence", id: false, charset: "utf8mb3" do |t|
      t.column :id, :bigint, primary_key: true, auto_increment: false, null: false, default: nil
      t.column :next_id, :bigint
      t.column :cache, :bigint
    end

    create_sequence(:saved_notification_entries_seq)
  end
end
