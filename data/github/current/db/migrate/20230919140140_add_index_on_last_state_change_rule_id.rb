# typed: true

class AddIndexOnLastStateChangeRuleId < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::RepositoriesNotify

  def change
    change_table :repository_vulnerability_alerts, bulk: true do |t|
      t.index [:last_state_change_rule_id], name: "index_rvas_on_last_state_change_rule_id"
    end
  end
end
