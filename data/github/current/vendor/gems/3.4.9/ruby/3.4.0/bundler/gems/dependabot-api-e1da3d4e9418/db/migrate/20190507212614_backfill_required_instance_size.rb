# frozen_string_literal: true

class BackfillRequiredInstanceSize < ActiveRecord::Migration[6.0]
  def change
    UpdateConfig::INSTANCE_SIZE_MAP.each do |dyno_size, instance_size|
      UpdateConfig.
        where(required_dyno_size: dyno_size).
        update_all(required_instance_size: instance_size)
    end

    change_column_null :update_configs, :required_instance_size, false
  end
end
