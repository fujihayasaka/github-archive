# typed: true
class RemoveStatusesFromRepositoriesChecks < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def change
    # Nothing to do...
  end
end
