# typed: true

class ChangeColumnNullVulnerabilitiesCreatedById < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Notify)

  def up
    change_column_null :vulnerabilities, :created_by_id, true
  end

  def down
    change_column_null :vulnerabilities, :created_by_id, false
  end
end
