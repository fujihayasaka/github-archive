# typed: true
# frozen_string_literal: true

module Issue::PrefillHelper
  extend T::Helpers

  requires_ancestor { Object }

  # Prefills associations with available records ONLY. All associations are marked as loaded but no queries are performed
  #
  # collection        - An Array of ActiveRecord::Base objects
  # relation          - A Symbol with the relationship name
  # available_records - An Array of ActiveRecord::Base objects available for preloading, exhaustive for the given collection and relation
  #
  # Returns nothing.
  def prefill_from_exhaustive_available_records(collection, relation, available_records: [])
    collection = Array.wrap(collection).compact
    ids_by_primary_key = Hash.new do |h, primary_key|
      h[primary_key] = available_records.map { |record| record[primary_key] }.to_set
    end

    records_to_prefill, records_to_mark_as_loaded = collection.partition do |record|
      association = record.association(relation)
      if association.klass
        primary_key = association.reflection.join_primary_key(association.klass)
        foreign_key = association.reflection.join_foreign_key
        ids_by_primary_key[primary_key].include?(record[foreign_key])
      end
    end

    # Mark these associations as loaded to prevent re-executing queries we know won't return any records
    records_to_mark_as_loaded.each { |record| record.association(relation).loaded! }
    GitHub::PrefillAssociations.prefill_associations(records_to_prefill, relation, available_records: available_records)
  end

  # args: the arguments to send to the `async_method` (execting an array)
  # kwargs: the keyword arguments to send to the `async method` (expecting a hash of 'keyword'->'value')
  def async_preload_attribute(models, attribute, async_method, args = [], kwargs = {})
    return Promise.resolve unless models.any?

    klass = T.must(self.class.name).demodulize.downcase
    method = T.must(T.must(caller_locations(1, 1))[0]).base_label
    timer = Timer.new
    span_name = "async_preload_attribute::#{klass}::#{method}::#{attribute}"
    mysql_count_start = GitHub::MysqlInstrumenter.query_count
    model_count = T.unsafe(self).model_count(models)

    result = GitHub.tracer.in_span(span_name, kind: :internal) do |span|
      timer.start

      inner_result = Promise.all(models.map { |model| model.send(async_method, *args, **kwargs) }).then do |results|
        timer.stop
        models.each_with_index do |model, index|
          model.preload_attr(attribute, results[index])
        end
      end
      mysql_count = GitHub::MysqlInstrumenter.query_count
      span.set_attribute("mysql_queries", mysql_count - mysql_count_start)
      span.set_attribute("model_count", model_count)

      inner_result
    end

    GitHub.dogstats.distribution("async_preload_attribute.dist.time", timer.elapsed_ms, tags: [
      "class:#{klass}", "method:#{method}", "attribute:#{attribute}.#{async_method}", "model_count:#{model_count}"
    ])

    result
  end

  def model_count(models)
    case models.size
    when 0
      "0"
    when 1..10
      "1-10"
    when 11..50
      "11-50"
    when 51..100
      "51-100"
    when 101..500
      "101-500"
    else
      "500-X"
    end
  end
end
