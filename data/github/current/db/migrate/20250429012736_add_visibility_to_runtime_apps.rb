# typed: true
# frozen_string_literal: true

class AddVisibilityToRuntimeApps < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    add_column :runtime_apps, :visibility, :integer, default: 0
  end
end
