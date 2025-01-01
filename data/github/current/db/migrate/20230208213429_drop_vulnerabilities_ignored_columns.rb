# typed: true
class DropVulnerabilitiesIgnoredColumns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def up
    # we need to remove :created_by_id, :published_by_id, :withdrawn_by_id, :identifier, :source_identifier, :source
    # these are currently ignored_columns in the model.
    change_table :vulnerabilities, bulk: true do |t|
      t.remove_index name: "index_vulnerabilities_on_identifier"
      t.remove_index name: "index_vulnerabilities_on_source_and_source_identifier"
      t.remove :identifier
      t.remove :created_by_id
      t.remove :published_by_id
      t.remove :withdrawn_by_id
      t.remove :source_identifier
      t.remove :source
    end
  end

  def down
    change_table :vulnerabilities, bulk: true do |t|
      t.index [:identifier],
        unique: false,
        name: "index_vulnerabilities_on_identifier"
      t.index [:source, :source_identifier],
        unique: true,
        name: "index_vulnerabilities_on_source_and_source_identifier"

      t.column :identifier, :string, limit: 255, null: true # varchar 255
      t.column :created_by_id, :bigint, unsigned: true
      t.column :published_by_id, :bigint, unsigned: true
      t.column :withdrawn_by_id, :bigint, unsigned: true
      t.column :source_identifier, :string, limit: 128, null: true # varchar 128
      t.column :source, :string, limit: 64, null: true # varchar 64
    end
  end
end
