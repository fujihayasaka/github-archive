# frozen_string_literal: true

class AllowNullSeverity < ActiveRecord::Migration[5.1]
  def up
    change_column_null :advisories, :severity, true
    execute "UPDATE advisories SET severity = 3 WHERE severity = 4"
    execute "UPDATE advisories SET severity = 2 WHERE severity = 3"
    execute "UPDATE advisories SET severity = 1 WHERE severity = 2"
    execute "UPDATE advisories SET severity = 0 WHERE severity = 1"
    execute "UPDATE advisories SET severity = NULL WHERE severity = 0"
    change_column_default :advisories, :severity, nil
  end

  def down
    change_column_default :advisories, :severity, 0
    execute "UPDATE advisories SET severity = 4 WHERE severity = 3"
    execute "UPDATE advisories SET severity = 3 WHERE severity = 2"
    execute "UPDATE advisories SET severity = 2 WHERE severity = 1"
    execute "UPDATE advisories SET severity = 1 WHERE severity = 0"
    execute "UPDATE advisories SET severity = 0 WHERE severity IS NULL"
    change_column_null :advisories, :severity, false
  end
end
