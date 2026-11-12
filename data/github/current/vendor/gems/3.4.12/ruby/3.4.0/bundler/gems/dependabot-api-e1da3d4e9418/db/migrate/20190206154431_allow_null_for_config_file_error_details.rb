# frozen_string_literal: true

class AllowNullForConfigFileErrorDetails < ActiveRecord::Migration[6.0]
  def change
    change_column_null :config_file_errors, :error_details, true
  end
end
