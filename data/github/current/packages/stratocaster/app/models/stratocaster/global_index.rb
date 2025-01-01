# typed: true
# frozen_string_literal: true

class Stratocaster::GlobalIndex < ApplicationRecord::Mysql5
  self.table_name = "global_stratocaster_indexes"

  scope :by_key, -> (key) { where(index_key: key) }
  scope :by_key_value, -> (key, value) { where(index_key: key, value: value) }

  def self.insert(keys, value)
    # Strip milliseconds from the current time. If we don't do that, we will send a timestamp with a fractional
    # part to MySQL, and if that fractional part is >=0.5, MySQL will round it up, thus inserting a future
    # timestamp.
    # This will be an issue when fetching back the value, as we are defining a window for modified_at that does
    # _not_ involve future timestamps.
    now = Time.current.floor
    rows = keys.map { |key| [key, value, now] }
    ActiveRecord::Base.connected_to(role: :writing) do
      self.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows)))
        INSERT INTO global_stratocaster_indexes (`index_key`, value, modified_at)
        :rows
      SQL
    end
    GitHub.dogstats.distribution("stratocaster.global_indexer", rows.count, tags: ["operation:insert"])
  end

  def self.purge(keys, value)
    by_key_value(keys, value).delete_all
  end

  def self.values(key, limit, min_age = nil, max_age = nil)
    record_scope = by_key(key)

    if min_age && max_age
      record_scope = record_scope.where("modified_at BETWEEN ? AND ?", max_age.ago, min_age.ago)
    end

    record_scope.
      order("modified_at DESC, id DESC").
      limit(limit).pluck(:value)
  end

  def self.clear_keys(keys)
    by_key(keys).delete_all
  end
end
