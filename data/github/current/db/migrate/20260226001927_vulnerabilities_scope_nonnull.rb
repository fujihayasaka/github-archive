# typed: true
# frozen_string_literal: true

class VulnerabilitiesScopeNonnull < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def up
    change_column_null :vulnerabilities, :visibility_scope, false, "open_source"
  end

  def down
    change_column_null :vulnerabilities, :visibility_scope, true
  end
end
