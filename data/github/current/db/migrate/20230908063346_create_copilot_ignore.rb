# typed: true

class CreateCopilotIgnore < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    create_table :copilot_ignores, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :resource, polymorphic: true, index: { unique: true }, null: false, comment: "The repository or organization that owns this exclusion document"
      t.blob :document, default: nil, index: false, comment: "The exclusion document itself"
      t.bigint :updated_by_id, unsigned: true, index: false, null: true, comment: "The user who last updated the record"
      t.timestamps
    end
  end
end
