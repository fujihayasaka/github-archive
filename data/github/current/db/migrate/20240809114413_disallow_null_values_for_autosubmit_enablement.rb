# typed: true

class DisallowNullValuesForAutosubmitEnablement < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def up
    change_column_null :security_configurations, :dependency_graph_autosubmit_action, false
  end

  def down
    change_column_null :security_configurations, :dependency_graph_autosubmit_action, true
  end
end
