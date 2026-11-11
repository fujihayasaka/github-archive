class AbuseReportsUseBigint < ActiveRecord::Migration[7.2]

  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def up
    change_table :abuse_reports, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :reporting_user_id, :bigint, unsigned: true, null: true, default: nil
      t.change :reported_user_id, :bigint, unsigned: true, null: false
      t.change :reported_content_id, :bigint, unsigned: true, null: true, default: nil
      t.change :repository_id, :bigint, unsigned: true, null: true, default: nil
    end
  end

  def down
    change_table :abuse_reports, bulk: true do |t|
      t.change :id, :int, unsigned: true, null: false, auto_increment: true
      t.change :reporting_user_id, :int, unsigned: true, null: true, default: nil
      t.change :reported_user_id, :int, unsigned: true, null: false
      t.change :reported_content_id, :int, unsigned: true, null: true, default: nil
      t.change :repository_id, :int, unsigned: true, null: true, default: nil
    end
  end
end
