# typed: true

class CreateExemptionResponses < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Repositories)


  def change
    create_table :exemption_responses, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :exemption_request_id, unsigned: true
      t.bigint :reviewer_id, null: false, unsigned: true
      t.column :status, :tinyint, null: false, unsigned: true, default: 0
      t.string :message, limit: 2048
      t.json :metadata
      t.timestamps

      t.index [:exemption_request_id], name: "index_exemption_responses_exemption_request"
    end
  end
end
