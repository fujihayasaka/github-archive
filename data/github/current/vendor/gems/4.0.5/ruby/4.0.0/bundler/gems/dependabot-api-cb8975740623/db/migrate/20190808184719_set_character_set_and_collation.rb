# frozen_string_literal: true

class SetCharacterSetAndCollation < ActiveRecord::Migration[6.0]
  def change
    return unless Rails.env.production?

    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      ALTER DATABASE deltaforce_production
      CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
    SQL

    ActiveRecord::Base.connection.execute(<<~SQL.squish)
      ALTER TABLE received_push_events
      CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
    SQL
  end
end
