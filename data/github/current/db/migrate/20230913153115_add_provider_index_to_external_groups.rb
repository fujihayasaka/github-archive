# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class AddProviderIndexToExternalGroups < ActiveRecord::Migration[7.1]
  def up
    change_table :external_groups, bulk: true do |t|
      t.index [:provider_id, :provider_type], name: "index_external_groups_on_provider_id_and_provider_type"
    end
  end

  def down
    change_table :external_groups, bulk: true do |t|
      t.remove_index [:provider_id, :provider_type], name: "index_external_groups_on_provider_id_and_provider_type"
    end
  end
end
