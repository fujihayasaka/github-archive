# frozen_string_literal: true

class AddAssignerIDToCVEs < ActiveRecord::Migration[7.0]
  def change
    add_column :cves, :assigner_id, :bigint
  end
end
