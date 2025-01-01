# typed: true

class AddExclusionRuleToFlipperFeatures < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Features)

  def change
    add_column :flipper_features, :exclusion_rule, :integer, null: true, unsigned: true
  end
end
