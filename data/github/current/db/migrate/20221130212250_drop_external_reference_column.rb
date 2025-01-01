# typed: true
class DropExternalReferenceColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def up
    remove_column :vulnerabilities, :external_reference
  end

  def down
    add_column :vulnerabilities, :external_reference, :string, limit: 255, null: true, after: :classification
  end
end
