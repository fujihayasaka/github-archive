class AddPreventSelfReviewToGates < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)
  def change
    add_column :gates, :prevent_self_review, :boolean, null: false, default: false
  end
end
