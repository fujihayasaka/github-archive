# typed: true

class AddActionsStepFieldsToTokenScanResultLocationsV2 < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table :token_scan_result_locations_v2, bulk: true do |t|
      t.column :actions_step_number, "int(11)", null: true, unsigned: true,
        comment: "the 1-based step number within the Actions job where the secret was found"
      t.column :actions_step_start_line, "int(11)", null: true, unsigned: true,
        comment: "the 1-based line number relative to the start of the step where the secret was found"
    end
  end

  def down
    change_table :token_scan_result_locations_v2, bulk: true do |t|
      t.remove :actions_step_number, :actions_step_start_line
    end
  end
end
