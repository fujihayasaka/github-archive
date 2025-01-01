# typed: true
# frozen_string_literal: true
require "github/result"

module Stratocaster::Indexers
  class MysqlIndexer

    # This is a KV store that access data in `stratocaster_indexes`, inspired by
    # GitHub::KV, but handling a different table structure and semantics:
    # - Stratocaster indexes never expire
    # - Stratocaster indexes don't have a last update date
    #
    # Key and value lengths are not validated either as this is not a public
    # api aimed at being used at any place, but only from instances of
    # Stratocaster::Indexers::MysqlIndexer
    #
    class Store
      class UnavailableError < StandardError
      end

      class MissingConnectionError < StandardError
      end

      def self.create
        @store ||= new
      end

      # get :: String -> Result<String | nil>
      #
      # Gets the value of the specified key.
      #
      # Example:
      #
      #   get("foo")
      #     # => #<Result value: "bar">
      #
      #   get("octocat")
      #     # => #<Result value: nil>
      #
      def get(key)
        mget([key]).map { |values| values[0] }
      end

      # mget :: [String] -> Result<[String | nil]>
      #
      # Gets the values of all specified keys. Values will be returned in the
      # same order as keys are specified. nil will be returned in place of a
      # String for keys which do not exist.
      #
      # Example:
      #
      #   mget(["foo", "octocat"])
      #     # => #<Result value: ["bar", nil]
      #
      def mget(keys)
        GitHub::Result.new do
          kvs = ActiveRecord::Base.connected_to(role: :reading) do
            ApplicationRecord::Mysql5.connection.select_rows(Arel.sql(<<-SQL, keys: keys)).to_h
              SELECT `index_key`, value FROM stratocaster_indexes WHERE `index_key` IN (:keys)
            SQL
          end
          res = keys.map { |key| kvs[key] }
          GitHub.dogstats.distribution("stratocaster.mysql_indexer", keys.count, tags: ["operation:mget"])
          res
        end
      end

      # set :: String, String
      #
      # Sets the specified key to the specified value. Returns nil. Raises on
      # error.
      #
      # Example:
      #
      #   set("foo", "bar")
      #     # => nil
      #
      def set(key, value)
        mset([[key, value]])
      end

      # mset :: [[String, String]*]
      #
      # Sets the specified hash keys to their associated values. Returns nil. Raises on error.
      #
      # Example:
      #
      #   mset([["foo", "bar"], ["baz", "quux"]])
      #     # => nil
      #
      def mset(rows)
        encapsulate_error do
          rows.map! { |key, value| [key, GitHub::SQL::ArelLiterals.binary(value)] }
          ActiveRecord::Base.connected_to(role: :writing) do
            ApplicationRecord::Mysql5.connection.insert(Arel.sql(<<-SQL, rows: Arel::Nodes::ValuesList.new(rows)))
              INSERT INTO stratocaster_indexes (`index_key`, value)
              :rows
              ON DUPLICATE KEY UPDATE
                value = VALUES(value)
            SQL
          end
          GitHub.dogstats.distribution("stratocaster.mysql_indexer", rows.count, tags: ["operation:mset"])
        end
        nil
      end

      # del :: String -> nil
      #
      # Deletes the specified key. Returns nil. Raises on error.
      #
      # Example:
      #
      #   del("foo")
      #     # => nil
      #
      def del(key)
        mdel([key])
      end

      # mdel :: String -> nil
      #
      # Deletes the specified keys. Returns nil. Raises on error.
      #
      # Example:
      #
      #   mdel(["foo", "octocat"])
      #     # => nil
      #
      def mdel(keys)
        encapsulate_error do
          ApplicationRecord::Mysql5.connection.delete(Arel.sql(<<-SQL, keys: keys))
            DELETE FROM stratocaster_indexes WHERE `index_key` IN (:keys)
          SQL
          GitHub.dogstats.distribution("stratocaster.mysql_indexer", keys.count, tags: ["operation:mdel"])
        end
        nil
      end

      private

      def encapsulate_error
        yield
      rescue SystemCallError, ActiveRecord::StatementInvalid => e
        raise UnavailableError, "#{e.class}: #{e.message}"
      end
    end
  end
end
