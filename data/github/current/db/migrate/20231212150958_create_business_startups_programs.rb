class CreateBusinessStartupsPrograms < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :business_startups_programs, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :business_id, null: false, unsigned: true, comment: "business which belongs to startups program"
      t.column :status, "tinyint unsigned", null: false, comment: "enum representing the status of the business in the startups program"
      t.json :emails_sent_at, null: true, comment: "represents emails sent to the business where key is type of email and value is the timestamp when the email was sent"

      t.timestamps
    end

    add_index :business_startups_programs, :business_id, name: "index_business_startups_programs"
  end
end
