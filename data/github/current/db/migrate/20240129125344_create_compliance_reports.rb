class CreateComplianceReports < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    create_table :compliance_reports, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :slug, :string, null: false, index: { unique: true }
      t.column :report_type, :string, null: false
      t.column :parent_id, :bigint, unsigned: true, null: true
      t.column :title, :string, null: false
      t.column :coverage_period, :string, null: true
      t.column :description, :text, null: false
      t.column :filename, :string, null: true
      t.column :url, :text, null: true
      t.column :display_order, :integer, null: true
      t.column :published, :boolean, null: false, default: true
      t.timestamps
    end
  end
end
