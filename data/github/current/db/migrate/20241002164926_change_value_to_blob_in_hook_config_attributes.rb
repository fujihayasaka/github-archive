# typed: true
# frozen_string_literal: true

class ChangeValueToBlobInHookConfigAttributes < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Hooks)

  def up
    # Change from VARBINARY(1024) to BLOB to ensure
    # there is enough space for the ciphertext + metadata
    change_column :hook_config_attributes, :value, :blob
  end

  def down
    # Keep the column type as BLOB since the values inserted
    # since the update might be too large to fit into their
    # old size
    change_column :hook_config_attributes, :value, :blob
  end
end
