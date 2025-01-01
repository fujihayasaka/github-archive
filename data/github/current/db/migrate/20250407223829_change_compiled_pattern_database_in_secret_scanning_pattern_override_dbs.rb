# typed: strict
# frozen_string_literal: true

class ChangeCompiledPatternDatabaseInSecretScanningPatternOverrideDbs < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  sig { void }
  def up
    change_column :secret_scanning_pattern_override_dbs, :compiled_pattern_database, :mediumblob
  end

  sig { void }
  def down
    change_column :secret_scanning_pattern_override_dbs, :compiled_pattern_database, :blob
  end
end
