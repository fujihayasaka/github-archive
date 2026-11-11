# typed: true

class SecretScanningScansAqueductColumnExpansion < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table :secret_scanning_scans, bulk: true do |t|
      t.change :aqueduct_job_id, "varchar(255)", null: true, comment: "The most recent aqueduct job id for this job_group", charset: "ascii", collation: "ascii_general_ci"
    end
  end

  def down
    change_table :secret_scanning_scans, bulk: true do |t|
      t.change :aqueduct_job_id, "char(36)", null: true, comment: "The most recent aqueduct job id for this job_group"
    end
  end
end
