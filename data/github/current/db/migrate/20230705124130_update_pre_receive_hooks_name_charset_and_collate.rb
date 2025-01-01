# typed: true

class UpdatePreReceiveHooksNameCharsetAndCollate < ActiveRecord::Migration[7.1]
  def up
    connection.execute(<<~SQL)
      ALTER TABLE pre_receive_hooks
      MODIFY `name` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL ;
    SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE pre_receive_hooks
      MODIFY `name` VARCHAR(255) NOT NULL ;
    SQL
  end
end
