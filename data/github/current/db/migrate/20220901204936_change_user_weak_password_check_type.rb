# typed: false

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint

class ChangeUserWeakPasswordCheckType < ActiveRecord::Migration[7.1]
  def self.up
    # Change from VARBINARY(128) to BINARY to ensure
    # there is enough space for the ciphertext + metadata
    change_column :users, :weak_password_check_result, :binary
  end

  def self.down
    # Keep the column type as binary since the values inserted
    # since the update might be too large to fit into their
    # old size
    change_column :users, :weak_password_check_result, :binary
  end
end
