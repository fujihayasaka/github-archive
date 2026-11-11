# frozen_string_literal: true

class AddLabelSettingsToLabels < ActiveRecord::Migration[7.1]
  def change
    add_column :labels, :label_settings, :json
  end
end
