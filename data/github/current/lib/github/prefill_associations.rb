# typed: true
# frozen_string_literal: true

module GitHub
  # Helps preload ActiveRecord associations in collections of records to
  # minimize the number of queries.
  module PrefillAssociations
    extend self

    # Efficiently prefill an ActiveRecord relation. This
    # reuses existing Rails logic to implement this. The
    # relation allows for similar constructs as the Rails
    # :include syntax.
    #
    # collection        - An Array of ActiveRecord::Base objects
    # relation          - An Array of Symbols & Hashes (or just a Hash) representing the relationship name(s)
    # available_records - An Array of ActiveRecord::Base objects available for preloading, limiting additional database queries
    #
    # Returns nothing.
    def prefill_associations(collection, relation, available_records: [])
      collection = Array.wrap(collection).compact
      available_records = Array.wrap(available_records).compact
      ActiveRecord::Associations::Preloader.new(records: collection, associations: relation, available_records: available_records).call
    end

    # Eagerly prefill a method defined via the `batch_method` Prelude helper
    def prefill_batch_method(collection, batch_method, *args)
      collection = Array.wrap(collection).compact
      # Using T.unsafe to support the Splat operator https://sorbet.org/docs/error-reference#7019
      T.unsafe(Prelude).preload(collection, batch_method, *args) if collection.any?
    end
  end
end
