# typed: strict
# frozen_string_literal: true

module GitHub::ColumnCount
  extend T::Helpers

  requires_ancestor { ActiveRecord::Base }

  # Public: Modify the current column count of this entity by one.
  #
  # increment - Boolean indicating whether the value should increase or decrease
  #
  # Returns a Boolean indicating success.
  sig do
    params(increment: T::Boolean, column_name: String).returns(T::Boolean)
  end
  def update_column_count(increment:, column_name:)
    klass = T.cast(self.class, T.class_of(ActiveRecord::Base))

    query = <<~SQL
      UPDATE #{klass.table_name}
      SET updated_at = CASE WHEN #{column_name} <> GREATEST(COALESCE(#{column_name}, 0) + :difference, 0)
                       THEN :now
                       ELSE updated_at
                       END,
        #{column_name} = GREATEST(COALESCE(#{column_name}, 0) + :difference, 0)
      WHERE id = :id
    SQL

    difference = increment ? 1 : -1
    sql = Arel.sql(query, id:, difference:, now: Time.now.utc)
    success = klass.connection.update(sql) == 1

    # Update the local value for immediate use, so we don't have to reload the record to fetch it:
    self[column_name] = [self[column_name] + difference, 0].max if success

    success
  end
end
