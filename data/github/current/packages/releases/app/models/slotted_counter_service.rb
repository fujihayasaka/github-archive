# typed: true
# frozen_string_literal: true

class SlottedCounterService
  def self.read_model
    ApplicationRecord::Ballast
  end

  def self.write_model
    ApplicationRecord::Ballast
  end

  # This is here for backwards compatibility. I wouldn't recommend using it
  # going forward. Instead just use the methods in the service. I would love to
  # see it removed from the models that do include it. The main reason it exists
  # is to return slotted count + old column count and to make prefilling easy.
  module Countable
    extend T::Sig
    extend T::Helpers

    requires_ancestor { ApplicationRecord::Base }

    def slotted_count_with(attr)
      read_attribute(attr).to_i + slotted_count
    end

    def slotted_count
      @slotted_count ||= SlottedCounterService.count(self)
    end

    def slotted_count=(value)
      @slotted_count = value
    end

    def slotted_count!(attr)
      if !GitHub.enterprise?
        SlottedCounterService.increment_aggregated_async(self)
      else
        SlottedCounterService.increment(self)
      end

      if attr && @slotted_count
        write_attribute(attr, read_attribute(attr).to_i + 1)
      end
    end
  end

  def self.increment(record)
    increment_type_and_id(record_type(record), record.id)
  end

  def self.increment_type_and_id(record_type, record_id, increment = 1)
    ActiveRecord::Base.connected_to(role: :writing) do
      statement = <<-SQL
        INSERT INTO slotted_counters (record_type, record_id, slot, count)
        VALUES (:record_type, :record_id, :slot, :increment)
        ON DUPLICATE KEY UPDATE count = count + :increment
      SQL

      binds = {
        record_type: record_type,
        record_id: record_id,
        slot: (SecureRandom.random_number(100)).to_i,
        increment: increment,
      }
      last_insert_id = write_model.connection.insert(Arel.sql(statement, **binds))
      last_insert_id.to_i > 0
    end
  end

  def self.increment_aggregated_async(record)
    # After a few weeks of experiments, 10 minutes interval seems to be the golden middle.
    # https://github.com/github/repos/issues/9006#issuecomment-1860078698
    interval = 600
    SlottedCounterIncrementAggregatedJob.enqueue_aggregated_per_interval([record_type(record), record.id], interval:)
  end

  def self.count(record)
    count_type_and_id(record_type(record), record.id)
  end

  def self.count_type_and_id(record_type, record_id)
    statement = <<-SQL
      SELECT SUM(`count`)
      FROM slotted_counters
      WHERE record_type = :record_type AND record_id = :record_id
    SQL
    binds = {
      record_type: record_type,
      record_id: record_id,
    }
    read_model.connection.select_value(Arel.sql(statement, **binds)).to_i
  end

  def self.prefill(records)
    return if records.blank?

    records.each { |record| record.slotted_count = 0 }

    by_type = records.group_by { |record| record_type(record) }
    by_type.each_pair do |record_type, records|
      prefill_by_type(record_type, records)
    end

    nil
  end

  def self.prefill_by_type(record_type, records)
    statement = <<-SQL
      SELECT record_type, record_id, SUM(`count`)
      FROM slotted_counters
      WHERE record_type = :record_type AND record_id IN (:record_ids)
      GROUP BY record_type, record_id
    SQL
    binds = {
      record_type: record_type,
      record_ids: records.map(&:id),
    }
    records_by_id = records.index_by(&:id)
    results = read_model.connection.select_rows(Arel.sql(statement, **binds))
    results.each do |(_record_type, record_id, count)|
      records_by_id[record_id].slotted_count = count.to_i
    end
  end
  class << self; private :prefill_by_type end

  def self.record_type(record)
    record.class.base_class.name
  end
  class << self; private :record_type end
end
