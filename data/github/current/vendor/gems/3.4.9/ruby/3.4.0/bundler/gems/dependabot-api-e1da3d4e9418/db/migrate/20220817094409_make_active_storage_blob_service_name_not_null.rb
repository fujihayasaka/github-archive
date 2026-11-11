# frozen_string_literal: true

class MakeActiveStorageBlobServiceNameNotNull < ActiveRecord::Migration[6.1]
  def change
    change_column_null :active_storage_blobs, :service_name, false
  end
end
