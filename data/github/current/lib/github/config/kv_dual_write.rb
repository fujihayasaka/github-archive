# typed: strict
# frozen_string_literal: true

require_relative "kv"
require_relative "flipper"

module GitHub
  module Config
    # GitHub::Config::DualWriteKV is a dual read/write wrapper around a source
    # and target GitHub::KV store.
    #
    # There are 2 progressive feature flags which can be used to control the behavior
    # of the dual writer at runtime.
    #
    #  1. dual_write:      Enables dual write behavior, including write error detection.
    #                      This mode handles write errors on the target by incrementing a metric,
    #                      but does not fail the operation. This mode is intended to be used to
    #                      determine load patterns on the target database before proceeding.
    #  2. dual_read:       Enables dual read behavior, including data mismatch detection.
    #                      This mode handles read errors on the target by incrementing a metric,
    #                      but does not fail the operation. Only enable this mode after the data
    #                      transition has been run, since otherwise it will detect mismatches for
    #                      all keys which have not been dual written
    #  3. write_to_target: Enables writing ONLY to the target KV store, disabling dual write. Once
    #                      this flag is enabled, the expectation is that data verification has been
    #                      completed. There is no rolling back once this flag is enabled.
    #
    class DualWriteKV
      extend T::Sig
      include GitHub::Memoizer

      # DualWriteKV::Flags is a configurable container for the feature flags used.
      #
      class Flags
        extend T::Sig

        sig { returns(T.nilable(Symbol)) }
        attr_reader :dual_read

        sig { returns(T.nilable(Symbol)) }
        attr_reader :dual_write

        sig { returns(T.nilable(Symbol)) }
        attr_reader :write_to_target

        sig { returns(T::Boolean) }
        attr_accessor :force_dual_read

        sig { returns(T::Boolean) }
        attr_accessor :force_dual_write

        sig { returns(T::Boolean) }
        attr_accessor :force_write_to_target

        # Convenience method to build a new Flags instance with consistent
        # feature flag names.
        #
        # The following calls are equivalent:
        #
        #     Flags.with_prefix(:example)
        #     Flags.new(dual_read: :example_dual_read,
        #       dual_write: :example_dual_write,
        #       write_to_target: :example_write_to_target)
        #
        sig do
          params(
            prefix: T.any(Symbol, String),
            force_dual_read: T::Boolean,
            force_dual_write: T::Boolean,
            force_write_to_target: T::Boolean,
          ).returns(T.attached_class)
        end
        def self.with_prefix(prefix, force_dual_read: false, force_dual_write: false, force_write_to_target: false)
          new(
            dual_read: :"#{prefix}_dual_read",
            dual_write: :"#{prefix}_dual_write",
            write_to_target: :"#{prefix}_write_to_target",
            force_dual_read:,
            force_dual_write:,
            force_write_to_target:,
          )
        end

        # initialize :: Symbol, Symbol, Symbol, Boolean, Boolean, Boolean -> nil
        #
        # Initialize a new Flags instance. The force_* parameters always override
        # any feature flag checks if both values are specified. If no feature flag
        # is specified then no enabled check is performed.
        #
        # dual_read:              - The feature flag name for dual read
        # dual_write:             - The feature flag name for dual write
        # write_to_target:        - The feature flag name for write to target
        # log_mismatched_values:  - The feature flag name for log mismatched values
        # force_dual_read:        - Explicit override for dual read
        # force_dual_write:       - Explicit override for dual write
        # force_write_to_target:  - Explicit override for writing to target
        #
        # Returns nothing.
        #
        sig do
          params(
            dual_read: T.nilable(Symbol),
            dual_write: T.nilable(Symbol),
            write_to_target: T.nilable(Symbol),
            log_mismatched_values: T.nilable(Symbol),
            force_dual_read: T::Boolean,
            force_dual_write: T::Boolean,
            force_write_to_target: T::Boolean,
          ).void
        end
        def initialize(
          dual_read: nil,
          dual_write: nil,
          write_to_target: nil,
          log_mismatched_values: nil,
          force_dual_read: false,
          force_dual_write: false,
          force_write_to_target: false
        )
          @dual_read = dual_read
          @dual_write = dual_write
          @write_to_target = write_to_target
          @log_mismatched_values = log_mismatched_values
          @force_dual_read = force_dual_read
          @force_dual_write = force_dual_write
          @force_write_to_target = force_write_to_target
        end

        # dual_read? :: nil -> Boolean
        #
        # Returns true if dual_read is enabled, false otherwise.
        #
        sig { returns(T::Boolean) }
        def dual_read?
          return true if @force_dual_read
          return GitHub.flipper.enabled?(@dual_read) if @dual_read
          false
        end

        # dual_write? :: nil -> Boolean
        #
        # Returns true if dual_write is enabled, false otherwise.
        #
        sig { returns(T::Boolean) }
        def dual_write?
          return true if @force_dual_write
          return GitHub.flipper.enabled?(@dual_write) if @dual_write
          false
        end

        # write_to_target? :: nil -> Boolean
        #
        # Returns true if write_to_target is enabled, false otherwise.
        #
        sig { returns(T::Boolean) }
        def write_to_target?
          return true if @force_write_to_target
          return GitHub.flipper.enabled?(@write_to_target) if @write_to_target
          false
        end

        # dual_read? :: nil -> Boolean
        #
        # Returns true if dual_read is enabled, false otherwise.
        #
        sig { returns(T::Boolean) }
        def log_mismatched_values?
          return false unless @log_mismatched_values

          GitHub.flipper.enabled?(@log_mismatched_values)
        end
      end

      # Converts from a source key to a target key
      module IKeyTransformer
        extend T::Helpers
        extend T::Sig

        interface!

        sig { abstract.params(key: String).returns(String) }
        def transform(key); end

        sig { abstract.params(prefix: String).returns(String) }
        def transform_prefix(prefix); end
      end

      class IdentityKeyTransformer
        extend T::Sig
        include IKeyTransformer

        sig { override.params(key: String).returns(String) }
        def transform(key) = key

        sig { override.params(prefix: String).returns(String) }
        def transform_prefix(prefix) = prefix
      end

      AnyTime = T.type_alias { T.any(Time, ActiveSupport::TimeWithZone) }

      sig { returns(String) }
      attr_reader :owner

      sig { returns(GitHub::KV) }
      attr_reader :kv_source

      sig { returns(GitHub::KV) }
      attr_reader :kv_target

      sig { returns(Flags) }
      attr_reader :flags

      # initialize :: String, KV, KV, Flags -> nil
      #
      # Initialize a new DualWriteKV instance.
      #
      # owner:     - The owning service for the target KV instance
      # kv_source: - The source KV instance
      # kv_target: - The target KV instance
      # flags:     - Feature flag names used to control dual write/read
      # shard_key_column: - The column used as the primary sharding key for vitess clusters
      # shard_key_value:  - The shard key value for this dual write instance
      # key_transformer:  - An IKeyTransformer to convert keys from the source format to the target format
      #
      # Returns nothing.
      sig do
        params(
          owner: String,
          kv_source: GitHub::KV,
          kv_target: GitHub::KV,
          flags: Flags,
          shard_key_column: T.nilable(T.any(String, Symbol)),
          shard_key_value: T.nilable(Integer),
          key_transformer: T.nilable(IKeyTransformer),
        ).void
      end
      def initialize(owner:, kv_source:, kv_target:, flags:, shard_key_column: nil, shard_key_value: nil, key_transformer: nil)
        @owner = owner
        @kv_source = kv_source
        @kv_target = kv_target
        @flags = flags
        @shard_key_column = shard_key_column
        @shard_key_value = shard_key_value
        @key_transformer = T.let(
          key_transformer || IdentityKeyTransformer.new,
          IKeyTransformer
        )
        @encapsulated_errors = T.let([
          ActiveRecord::ConnectionFailed,
          ActiveRecord::ConnectionNotEstablished,
          ActiveRecord::NoDatabaseError,
        ], T::Array[T.class_of(Exception)])
      end

      # get :: String -> Result<String | nil>
      #
      # Gets the value of the specified key.
      #
      # Example:
      #
      #   kv.get("foo")
      #     # => #<Result value: "bar">
      #
      #   kv.get("octocat")
      #     # => #<Result value: nil>
      #
      sig { params(key: String).returns(GitHub::Result) }
      def get(key)
        target_key = @key_transformer.transform(key)

        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:get"])
          @kv_target.get(target_key)
        elsif @flags.dual_read?
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:get"])
          res = @kv_source.get(key)
          begin
            GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:get"])
            cmp = @kv_target.get(target_key)
            source_value = res.value { nil }
            target_value = cmp.value { nil }
            if source_value != target_value
              GitHub.dogstats.increment("kv.migration.data_mismatch", tags: ["owner:#{@owner}", "action:get"])
              if @flags.log_mismatched_values?
                GitHub.logger.info(
                  "KV migration data mismatch",
                  owner: @owner,
                  key: key,
                  source_value: source_value,
                  target_value: target_value,
                )
              end
            end
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_read_error", tags: ["owner:#{@owner}", "action:get"])
          end
          res
        else
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:get"])
          @kv_source.get(key)
        end
      end

      # mget :: [String] -> Result<[String | nil]>
      #
      # Gets the values of all specified keys. Values will be returned in the
      # same order as keys are specified. nil will be returned in place of a
      # String for keys which do not exist.
      #
      # Example:
      #
      #   kv.mget(["foo", "octocat"])
      #     # => #<Result value: ["bar", nil]
      #
      sig { params(keys: T::Array[String]).returns(GitHub::Result) }
      def mget(keys)
        target_keys = keys.map { @key_transformer.transform(_1) }

        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:mget"])
          @kv_target.mget(target_keys)
        elsif @flags.dual_read?
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:mget"])
          res = @kv_source.mget(keys)
          begin
            GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:mget"])
            cmp = @kv_target.mget(target_keys)
            if res.value { nil } != cmp.value { nil }
              GitHub.dogstats.increment("kv.migration.data_mismatch", tags: ["owner:#{@owner}", "action:mget"])
              if @flags.log_mismatched_values?
                GitHub.logger.info(
                  "KV migration data mismatch",
                  owner: @owner,
                  key: keys,
                  source_value: res.value { nil },
                  target_value: cmp.value { nil },
                )
              end
            end
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_read_error", tags: ["owner:#{@owner}", "action:mget"])
          end
          res
        else
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:mget"])
          @kv_source.mget(keys)
        end
      end

      # mget_prefix:: [String] -> Result<{String: String} | {}>
      #
      # Gets the key/value pair for keys starting with the given prefix.
      #
      # Example:
      #
      #   kv.mget_prefix("foo")
      #     # => #<Result value: { "foo" => "bar" }>
      #
      sig { params(prefix: String).returns(GitHub::Result) }
      def mget_prefix(prefix)
        target_prefix = @key_transformer.transform_prefix(prefix)

        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:mget_prefix"])
          @kv_target.mget_prefix(target_prefix)
        elsif @flags.dual_read?
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:mget_prefix"])
          res = @kv_source.mget_prefix(prefix)
          begin
            GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:mget_prefix"])
            cmp = @kv_target.mget_prefix(target_prefix)
            if res.value { nil } != cmp.value { nil }
              GitHub.dogstats.increment("kv.migration.data_mismatch", tags: ["owner:#{@owner}", "action:mget_prefix"])
            end
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_read_error", tags: ["owner:#{@owner}", "action:mget_prefix"])
          end
          res
        else
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:mget_prefix"])
          @kv_source.mget_prefix(prefix)
        end
      end

      # set :: String, String, expires: Time? -> nil
      #
      # Sets the specified key to the specified value. Returns nil. Raises on
      # error.
      #
      # Example:
      #
      #   kv.set("foo", "bar")
      #     # => nil
      #
      sig { params(key: String, value: String, expires: T.nilable(AnyTime)).void }
      def set(key, value, expires: nil)
        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:set"])
          target_key = @key_transformer.transform(key)
          @kv_target.set(target_key, value, expires:)
        elsif @flags.dual_write?
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:set"])
          updated_rows = T.let(nil, T.untyped)
          @kv_source.connection.transaction do
            @kv_source.set(key, value, expires:)
            updated_rows = get_values_from_source(keys: [key])
          end

          begin
            GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:set"])
            set_values_on_target_if_newer(rows: updated_rows)
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_write_error", tags: ["owner:#{@owner}", "action:set"])
          end
        else
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:set"])
          @kv_source.set(key, value, expires:)
        end
      end

      # try_set :: String, String, expires: Time? -> nil
      #
      # Sets the specified key to the specified value. Returns true on success.
      # Returns false on UnavailableError. Raises on other errors.
      #
      # Example:
      #
      #  if kv.try_set("foo", "bar")
      #    # Key was set
      #  else
      #    # Fallback, if needed
      #  end
      #
      sig { params(key: String, value: String, expires: T.nilable(AnyTime)).void }
      def try_set(key, value, expires: nil)
        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:try_set"])
          target_key = @key_transformer.transform(key)
          @kv_target.try_set(target_key, value, expires:)
        elsif @flags.dual_write?
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:try_set"])
          res = T.let(false, T.untyped)
          updated_rows = T.let(nil, T.untyped)
          @kv_source.connection.transaction do
            res = @kv_source.try_set(key, value, expires:)
            updated_rows = get_values_from_source(keys: [key])
          end

          begin
            GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:try_set"])
            set_values_on_target_if_newer(rows: updated_rows)
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_write_error", tags: ["owner:#{@owner}", "action:try_set"])
          end
          res
        else
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:try_set"])
          @kv_source.try_set(key, value, expires:)
        end
      end

      # mset :: { String => String }, expires: Time? -> nil
      #
      # Sets the specified hash keys to their associated values, setting them to
      # expire at the specified time. Returns nil. Raises on error.
      #
      # Example:
      #
      #   kv.mset({ "foo" => "bar", "baz" => "quux" })
      #     # => nil
      #
      #   kv.mset({ "expires" => "soon" }, expires: 1.hour.from_now)
      #     # => nil
      #
      sig { params(kvs: T::Hash[String, String], expires: T.nilable(AnyTime)).void }
      def mset(kvs, expires: nil)
        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:mset"])
          target_kvs = kvs.map { |k, v| [@key_transformer.transform(k), v] }.to_h
          @kv_target.mset(target_kvs, expires:)
        elsif @flags.dual_write?
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:mset"])
          updated_rows = T.let(nil, T.untyped)
          @kv_source.connection.transaction do
            @kv_source.mset(kvs, expires:)
            updated_rows = get_values_from_source(keys: kvs.keys)
          end

          begin
            GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:mset"])
            set_values_on_target_if_newer(rows: updated_rows)
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_write_error", tags: ["owner:#{@owner}", "action:mset"])
          end
        else
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:mset"])
          @kv_source.mset(kvs, expires:)
        end
      end

      # exists :: String -> Result<Boolean>
      #
      # Checks for existence of the specified key.
      #
      # Example:
      #
      #   kv.exists("foo")
      #     # => #<Result value: true>
      #
      #   kv.exists("octocat")
      #     # => #<Result value: false>
      #
      sig { params(key: String).returns(GitHub::Result) }
      def exists(key)
        target_key = @key_transformer.transform(key)

        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:exists"])
          @kv_target.exists(target_key)
        elsif @flags.dual_read?
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:exists"])
          res = @kv_source.exists(key)
          begin
            GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:exists"])
            cmp = @kv_target.exists(target_key)
            if res.value { nil } != cmp.value { nil }
              GitHub.dogstats.increment("kv.migration.data_mismatch", tags: ["owner:#{@owner}", "action:exists"])
              if @flags.log_mismatched_values?
                GitHub.logger.info(
                  "KV migration data mismatch",
                  owner: @owner,
                  key: key,
                  source_value: res.value { nil },
                  target_value: cmp.value { nil },
                )
              end
            end
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_read_error", tags: ["owner:#{@owner}", "action:exists"])
          end
          res
        else
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:exists"])
          @kv_source.exists(key)
        end
      end

      # mexists :: [String] -> Result<[Boolean]>
      #
      # Checks for existence of all specified keys. Booleans will be returned in
      # the same order as keys are specified.
      #
      # Example:
      #
      #   kv.mexists(["foo", "octocat"])
      #     # => #<Result value: [true, false]>
      #
      sig { params(keys: T::Array[String]).returns(GitHub::Result) }
      def mexists(keys)
        target_keys = keys.map { @key_transformer.transform(_1) }

        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:mexists"])
          @kv_target.mexists(target_keys)
        elsif @flags.dual_read?
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:mexists"])
          res = @kv_source.mexists(keys)
          begin
            GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:mexists"])
            cmp = @kv_target.mexists(target_keys)
            if res.value { nil } != cmp.value { nil }
              GitHub.dogstats.increment("kv.migration.data_mismatch", tags: ["owner:#{@owner}", "action:mexists"])
              if @flags.log_mismatched_values?
                GitHub.logger.info(
                  "KV migration data mismatch",
                  owner: @owner,
                  key: keys,
                  source_value: res.value { nil },
                  target_value: cmp.value { nil },
                )
              end
            end
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_read_error", tags: ["owner:#{@owner}", "action:mexists"])
          end
          res
        else
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:mexists"])
          @kv_source.mexists(keys)
        end
      end

      # setnx :: String, String, expires: Time? -> Boolean
      #
      # Sets the specified key to the specified value only if it does not
      # already exist.
      #
      # Returns true if the key was set, false otherwise. Raises on error.
      #
      # Example:
      #
      #   kv.setnx("foo", "bar")
      #     # => false
      #
      #   kv.setnx("octocat", "monalisa")
      #     # => true
      #
      #   kv.setnx("expires", "soon", expires: 1.hour.from_now)
      #     # => true
      #
      sig { params(key: String, value: String, expires: T.nilable(AnyTime)).returns(T::Boolean) }
      def setnx(key, value, expires: nil)
        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:setnx"])
          target_key = @key_transformer.transform(key)
          @kv_target.setnx(target_key, value, expires:)
        elsif @flags.dual_write?
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:setnx"])
          set_value = T.let(false, T.untyped)
          updated_rows = T.let(nil, T.untyped)
          @kv_source.connection.transaction do
            set_value = @kv_source.setnx(key, value, expires:)
            if set_value
              updated_rows = get_values_from_source(keys: [key])
            end
          end

          if set_value
            begin
              GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:setnx"])
              set_values_on_target_if_newer(rows: updated_rows)
            rescue GitHub::KV::UnavailableError
              GitHub.dogstats.increment("kv.migration.dual_write_error", tags: ["owner:#{@owner}", "action:setnx"])
            end
          end
          set_value
        else
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:setnx"])
          @kv_source.setnx(key, value, expires:)
        end
      end

      # increment :: String, Integer, expires: Time? -> Integer
      #
      # Increment the key's value by an amount.
      #
      # key             - The key to increment.
      # amount          - The amount to increment the key's value by.
      #                   The user can increment by both positive and
      #                   negative values
      # expires         - When the key should expire.
      # touch_on_insert - Only when expires is specified. When true
      #                   the expires value is only touched upon
      #                   inserts. Otherwise the record is always
      #                   touched.
      #
      # Returns the key's value after incrementing.
      #
      sig { params(key: String, amount: Integer, expires: T.nilable(AnyTime), touch_on_insert: T::Boolean).returns(Integer) }
      def increment(key, amount: 1, expires: nil, touch_on_insert: false)
        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:increment"])
          target_key = @key_transformer.transform(key)
          @kv_target.increment(target_key, amount:, expires:, touch_on_insert:)
        elsif @flags.dual_write?
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:increment"])
          updated_rows = T.let(nil, T.untyped)
          new_value = T.let(0, Integer)
          @kv_source.connection.transaction do
            new_value = @kv_source.increment(key, amount:, expires:, touch_on_insert:)
            updated_rows = get_values_from_source(keys: [key])
          end

          begin
            GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:increment"])
            set_values_on_target_if_newer(rows: updated_rows)
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_write_error", tags: ["owner:#{@owner}", "action:increment"])
          end
          new_value
        else
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:increment"])
          @kv_source.increment(key, amount:, expires:, touch_on_insert:)
        end
      end

      # del :: String -> nil
      #
      # Deletes the specified key. Returns nil. Raises on error.
      #
      # Example:
      #
      #   kv.del("foo")
      #     # => nil
      #
      sig { params(key: String).void }
      def del(key)
        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:del"])
          target_key = @key_transformer.transform(key)
          @kv_target.del(target_key)
        elsif @flags.dual_write?
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:del"])
          deleted_rows = T.let(nil, T.untyped)
          @kv_source.connection.transaction do
            deleted_rows = get_values_from_source_for_delete(keys: [key])
            @kv_source.del(key)
          end

          begin
            GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:del"])
            delete_from_target_if_same(rows: deleted_rows)
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_write_error", tags: ["owner:#{@owner}", "action:del"])
          end
        else
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:del"])
          @kv_source.del(key)
        end
      end

      # mdel :: String -> nil
      #
      # Deletes the specified keys. Returns nil. Raises on error.
      #
      # Example:
      #
      #   kv.mdel(["foo", "octocat"])
      #     # => nil
      #
      sig { params(keys: T::Array[String]).void }
      def mdel(keys)
        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:mdel"])
          target_keys = keys.map { @key_transformer.transform(_1) }
          @kv_target.mdel(target_keys)
        elsif @flags.dual_write?
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:mdel"])
          deleted_rows = T.let(nil, T.untyped)
          @kv_source.connection.transaction do
            deleted_rows = get_values_from_source_for_delete(keys:)
            @kv_source.mdel(keys)
          end

          begin
            GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:mdel"])
            delete_from_target_if_same(rows: deleted_rows)
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_write_error", tags: ["owner:#{@owner}", "action:mdel"])
          end
        else
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:mdel"])
          @kv_source.mdel(keys)
        end
      end

      # mdel_prefix :: String -> nil
      #
      # Deletes the keys starting with the given prefix. Returns nil. Raises on error.
      #
      # Example:
      #
      #   kv.mdel_prefix("prefix")
      #     # => nil
      #
      sig { params(prefix: String).void }
      def mdel_prefix(prefix)
        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:mdel_prefix"])
          target_prefix = @key_transformer.transform_prefix(prefix)
          @kv_target.mdel_prefix(target_prefix)
        elsif @flags.dual_write?
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:mdel_prefix"])
          deleted_rows = T.let(nil, T.untyped)
          @kv_source.connection.transaction do
            deleted_rows = get_values_from_source_for_delete_prefix(prefix:)
            @kv_source.mdel_prefix(prefix)
          end

          begin
            GitHub.dogstats.increment("kv.migration.target.write", tags: ["owner:#{@owner}", "action:mdel_prefix"])
            delete_from_target_if_same(rows: deleted_rows)
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_write_error", tags: ["owner:#{@owner}", "action:mdel_prefix"])
          end
        else
          GitHub.dogstats.increment("kv.migration.source.write", tags: ["owner:#{@owner}", "action:mdel_prefix"])
          @kv_source.mdel_prefix(prefix)
        end
      end

      # ttl :: String -> Result<[Time | nil]>
      #
      # Returns the expires_at time for the specified key or nil.
      #
      # Example:
      #
      #  kv.ttl("foo")
      #    # => #<Result value: 2018-04-23 11:34:54 +0200>
      #
      #  kv.ttl("foo")
      #    # => #<Result value: nil>
      #
      sig { params(key: String).returns(GitHub::Result) }
      def ttl(key)
        target_key = @key_transformer.transform(key)

        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:ttl"])
          @kv_target.ttl(target_key)
        elsif @flags.dual_read?
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:ttl"])
          res = @kv_source.ttl(key)
          begin
            GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:ttl"])
            cmp = @kv_target.ttl(target_key)
            if res.value { nil } != cmp.value { nil }
              GitHub.dogstats.increment("kv.migration.data_mismatch", tags: ["owner:#{@owner}", "action:ttl"])
              if @flags.log_mismatched_values?
                GitHub.logger.info(
                  "KV migration data mismatch",
                  owner: @owner,
                  key: key,
                  source_value: res.value { nil },
                  target_value: cmp.value { nil },
                )
              end
            end
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_read_error", tags: ["owner:#{@owner}", "action:ttl"])
          end
          res
        else
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:ttl"])
          @kv_source.ttl(key)
        end
      end

      # mttl :: [String] -> Result<[Time | nil]>
      #
      # Returns the expires_at time for the specified key or nil.
      #
      # Example:
      #
      #  kv.mttl(["foo", "octocat"])
      #    # => #<Result value: [2018-04-23 11:34:54 +0200, nil]>
      #
      sig { params(keys: T::Array[String]).returns(GitHub::Result) }
      def mttl(keys)
        target_keys = keys.map { @key_transformer.transform(_1) }

        if @flags.write_to_target?
          GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:mttl"])
          @kv_target.mttl(target_keys)
        elsif @flags.dual_read?
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:mttl"])
          res = @kv_source.mttl(keys)
          begin
            GitHub.dogstats.increment("kv.migration.target.read", tags: ["owner:#{@owner}", "action:mttl"])
            cmp = @kv_target.mttl(target_keys)
            if res.value { nil } != cmp.value { nil }
              GitHub.dogstats.increment("kv.migration.data_mismatch", tags: ["owner:#{@owner}", "action:mttl"])
              if @flags.log_mismatched_values?
                GitHub.logger.info(
                  "KV migration data mismatch",
                  owner: @owner,
                  key: keys,
                  source_value: res.value { nil },
                  target_value: cmp.value { nil },
                )
              end
            end
          rescue GitHub::KV::UnavailableError
            GitHub.dogstats.increment("kv.migration.dual_read_error", tags: ["owner:#{@owner}", "action:mttl"])
          end
          res
        else
          GitHub.dogstats.increment("kv.migration.source.read", tags: ["owner:#{@owner}", "action:mttl"])
          @kv_source.mttl(keys)
        end
      end

      private

      sig { params(rows: T::Array[GetValuesForDeleteRow]).void }
      def delete_from_target_if_same(rows:)
        return if rows.blank?

        columns = %w[
          `key`
          `updated_at`
        ]
        all_values = rows.map do |r|
          target_key = @key_transformer.transform(r["key"])
          [target_key, r["updated_at"]].map { |v| @kv_target.connection.quote(v) }
        end

        if sharded?
          columns << quoted_shard_key_column
          all_values.each { |v| v << quoted_shard_key_value }
        end

        all_values = all_values.map { |v| "(#{v.join(",")})" }.join(", ")
        sql = <<~SQL
          DELETE FROM #{@kv_target.quoted_table_name}
          WHERE  (#{columns.join(", ")}) IN (#{all_values})
        SQL

        encapsulate_error { @kv_target.connection.delete(sql) }
      end

      # updates the values on the target kv to match the input data, only if
      # the existing data is older.
      sig { params(rows: T::Array[GetValuesRow]).void }
      def set_values_on_target_if_newer(rows:)
        return if rows.blank?

        columns = %w[
          `key`
          `value`
          `created_at`
          `updated_at`
          `expires_at`
        ]
        all_values = rows.map do |r|
          target_key = @key_transformer.transform(r["key"])
          [target_key] + r.values_at("value", "created_at", "updated_at", "expires_at")
        end

        if sharded?
          columns << quoted_shard_key_column
          all_values.each { |v| v << quoted_shard_key_value }
        end

        sql = <<~SQL
          INSERT INTO #{@kv_target.quoted_table_name} (#{columns.join(", ")})
          :values
          ON DUPLICATE KEY UPDATE
            value = IF(updated_at < VALUES(updated_at), VALUES(value), value),
            created_at = IF(updated_at < VALUES(updated_at), VALUES(created_at), created_at),
            expires_at = IF(updated_at < VALUES(updated_at), VALUES(expires_at), expires_at),
            updated_at = IF(updated_at < VALUES(updated_at), VALUES(updated_at), updated_at)
        SQL

        sql = Arel.sql(sql, values: Arel::Nodes::ValuesList.new(all_values))
        encapsulate_error { @kv_target.connection.insert(sql) }
      end

      GetValuesRow = T.type_alias { { "key" => String, "value" => String, "created_at" => AnyTime, "updated_at" => AnyTime, "expires_at" => AnyTime } }
      private_constant :GetValuesRow

      # gets the values from the database as raw rows with the following columns:
      #  `key`, `value`, `created_at`, `updated_at`, `expires_at`
      sig { params(keys: T::Array[String]).returns(T::Array[GetValuesRow]) }
      def get_values_from_source(keys:)
        quoted_keys = keys.map { |k| @kv_source.connection.quote(k) }.join(", ")
        sql = <<~SQL
          SELECT  `key`, `value`, `created_at`, `updated_at`, `expires_at`
          FROM    #{@kv_source.quoted_table_name}
          WHERE   `key` IN (#{quoted_keys})
        SQL

        encapsulate_error { @kv_source.connection.select_all(sql).to_a || [] }
      end

      # gets the values from the database as raw rows with the following columns:
      #  `key`, `updated_at`
      sig { params(keys: T::Array[String]).returns(T::Array[GetValuesForDeleteRow]) }
      def get_values_from_source_for_delete(keys:)
        quoted_keys = keys.map { |k| @kv_source.connection.quote(k) }.join(", ")
        sql = <<~SQL
          SELECT  `key`, `updated_at`
          FROM    #{@kv_source.quoted_table_name}
          WHERE   `key` IN (#{quoted_keys})
          FOR UPDATE
        SQL

        encapsulate_error { @kv_source.connection.select_all(sql).to_a || [] }
      end

      GetValuesForDeleteRow = T.type_alias { { "key" => String, "updated_at" => AnyTime } }
      private_constant :GetValuesForDeleteRow

      # gets the values from the database as raw rows with the following columns:
      #  `key`, `updated_at`
      sig { params(prefix: String).returns(T::Array[GetValuesForDeleteRow]) }
      def get_values_from_source_for_delete_prefix(prefix:)
        sanitized = ActiveRecord::Base.sanitize_sql_like(prefix)
        quoted_prefix = @kv_source.connection.quote(sanitized + "%")
        sql = <<~SQL
          SELECT  `key`, `updated_at`
          FROM    #{@kv_source.quoted_table_name}
          WHERE   `key` LIKE #{quoted_prefix}
          FOR UPDATE
        SQL

        encapsulate_error { @kv_source.connection.select_all(sql).to_a || [] }
      end

      sig do
        type_parameters(:Result)
          .params(block: T.proc.returns(T.type_parameter(:Result)))
          .returns(T.type_parameter(:Result))
      end
      def encapsulate_error(&block)
        yield
      rescue *@encapsulated_errors => error
        raise GitHub::KV::UnavailableError, "#{error.class}: #{error.message}"
      end

      sig { returns(String) }
      memoize def quoted_shard_key_column
        @kv_target.connection.quote_column_name(@shard_key_column)
      end

      sig { returns(String) }
      memoize def quoted_shard_key_value
        @kv_target.connection.quote(@shard_key_value)
      end

      sig { returns(T::Boolean) }
      def sharded?
        @shard_key_column.present? && @shard_key_value.present?
      end
    end
  end

  extend Config::KV
end
