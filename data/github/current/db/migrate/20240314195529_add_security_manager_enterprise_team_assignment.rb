class AddSecurityManagerEnterpriseTeamAssignment < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :enterprise_team_assignments, bulk: true do |t|
      t.change   :assignment_type, "enum('copilot','security_manager')", null: false
    end
  end

  def down
    change_table :enterprise_team_assignments, bulk: true do |t|
      t.change   :assignment_type, "enum('copilot')", null: false
    end
  end
end
