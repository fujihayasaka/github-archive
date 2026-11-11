# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
# several columns cannot be converted to bigint yet because the associated tables still use integer
class AddIndexToAdvisoryCredits < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    add_index :advisory_credits, [:accepted_at, :vulnerability_id]
  end
end
