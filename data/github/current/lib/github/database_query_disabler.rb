# typed: true
# frozen_string_literal: true

module GitHub
  module DatabaseQueryDisabler
    extend T::Helpers
    requires_ancestor { ActiveRecord::Base }

    DISABLE_KEY = "database_query_disabler_clusters"

    class DatabaseDisabledError < ActiveRecord::DatabaseConnectionError
      MSG_SUFFIX = <<~MSG.freeze
        \n\nThis error is typically raised by staff to test database query resilience.

        See https://thehub.github.com/epd/engineering/dev-practicals/graceful-degradation/ for more details
      MSG

      def initialize(msg)
        super(msg + MSG_SUFFIX)
      end
    end

    module ClassMethods
      extend T::Helpers
      requires_ancestor { T.class_of(ActiveRecord::Base) }

      def queries_raise_exceptions?
        Thread.current[DISABLE_KEY]&.include?(self.connection_class_for_self)
      end

      def disable_queries_to_databases(databases, &block)
        databases = Array(databases)
        existing_disabled_databases = Thread.current[DISABLE_KEY]

        Thread.current[DISABLE_KEY] = (existing_disabled_databases || []) + databases.map do |db|
          db.connection_class_for_self
        end

        block.call
      ensure
        Thread.current[DISABLE_KEY] = existing_disabled_databases
      end

      def disable_queries_to_database(&block)
        disable_queries_to_databases(self, &block)
      end
    end
    mixes_in_class_methods(ClassMethods)
  end
end
