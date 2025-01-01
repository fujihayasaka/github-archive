# typed: true

class AddNotNullConstraintToNameOnRepositoryRulesets < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_column_null :repository_rulesets, :name, false
  end
end
