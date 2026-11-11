# frozen_string_literal: true

class AddTenantShortcode < ActiveRecord::Migration[7.0]
  def change
    add_column :tenants, :shortcode, :string
  end
end
