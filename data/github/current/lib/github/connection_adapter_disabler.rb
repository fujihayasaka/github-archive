# typed: true
# frozen_string_literal: true

module GitHub
  # Implements methods defined in the
  # ActiveRecord::ConnectionAdapters::AbstractAdapter class that enable us to
  # intentionally break queries to a specific database.
  module ConnectionAdapterDisabler
    extend T::Helpers
    requires_ancestor { ActiveRecord::ConnectionAdapters::AbstractAdapter }

    # Override #query, so Resilient::Trilogy::Query can't call any of the
    # other methods while inside of a circuitbreaker, potentially tripping it.
    def query(*args)
      if connection_class&.queries_raise_exceptions?
        error = GitHub::DatabaseQueryDisabler::DatabaseDisabledError.new("queries to #{connection_class.name} are disabled.")
        error.set_pool(pool) if error.respond_to?(:set_pool) && defined?(pool)
        raise error
      end

      super
    end
    ruby2_keywords :query if respond_to?(:ruby2_keywords, true)

    def raw_execute(*args)
      if connection_class&.queries_raise_exceptions?
        error = GitHub::DatabaseQueryDisabler::DatabaseDisabledError.new("queries to #{connection_class.name} are disabled.")
        error.set_pool(pool) if error.respond_to?(:set_pool) && defined?(pool)
        raise error
      end

      super
    end
    ruby2_keywords :raw_execute if respond_to?(:ruby2_keywords, true)
  end
end
