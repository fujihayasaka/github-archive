# typed: true
# frozen_string_literal: true

require "github/query_batching/iterator_builder"
require "github/query_batching/scope_iterator"
require "github/sql/arel_literals"
require "github/sql/batched"
require "github/sql/batched_between"
require "github/sql/batched_builder"
require "github/sql/descending_batched_between"
require "github/encryption/no_op_key_provider"
require "github/encryption/github_key_provider"
require "github/encryption/github_previous_encryptor"
require "github/encryption/feature_flag_encrypted_type"
require "like_query"

module ApplicationRecord
  class Base < ActiveRecord::Base # rubocop:disable Rails/ApplicationRecord
    self.abstract_class = true

    DEFAULT_REPLICATION_WAIT_TIME_MILLIS = 5000

    autoload :GitHubSQLBuilder, "application_record/base/github_sql_builder"
    autoload :ThrottlerBuilder, "application_record/base/throttler_builder"
    autoload :BaseHelpers,      "application_record/base/base_helpers"

    include GitHub::Relay::GlobalIdentification
    include GitHub::BatchMethod

    include ThrottlerBuilder::DelegateMethods
    extend ThrottlerBuilder::DelegateMethods

    include BaseHelpers::Helpers
    extend BaseHelpers::Helpers

    extend LikeQuery
    include GitHub::BackgroundDependentDeletes

    # Scope for querying when a field does not match one of many possible values
    # You can use `where(field: [value1, value2])` as well, but when your array
    # is very large this performs better by avoiding Arel object allocations.
    scope :without_ids, ->(ids, field: "#{quoted_table_name}.#{quoted_primary_key}") { ids.any? ? where("#{field} NOT IN (?)", ids) : self }

    # Tell mysql to kill the query if it runs too long.  Intended as a safety
    # valve to make sure that inadvertently slow queries time out quickly
    # rather than in the timeout middleware where visibility is poor.
    scope :limit_execution_time, -> (limit_ms: 500) { optimizer_hints("MAX_EXECUTION_TIME(#{limit_ms})") }

    def self.belongs_to(name, scope = nil, **options)
      define_async_reflection_association(name)
      super
    end

    def self.has_one(name, scope = nil, **options)
      define_async_reflection_association(name)
      super
    end

    def self.has_many(name, scope = nil, **options, &block)
      define_async_reflection_association(name)
      super
    end

    def self.has_and_belongs_to_many(name, scope = nil, **options, &block)
      define_async_reflection_association(name)
      super
    end

    def self.define_async_reflection_association(name)
      generated_async_reflection_associations.module_eval do
        define_method("async_#{name}") do
          ::Platform::Loaders::ActiveRecordAssociation.load(self, name)
        end
      end
    end

    def self.generated_async_reflection_associations
      :GeneratedAsyncReflectionAssociations.yield_self do |name|
        const_defined?(name, false) ? const_get(name) : const_set(name, Module.new.tap { |mod| include mod })
      end
    end
    private_class_method :generated_async_reflection_associations

    def self.scoped
      all
    end

    def reset_memoized_attributes
    end

    def reload(*)
      reset_batch_methods
      reset_memoized_attributes
      super
    end

    def self.gtid_tracking_enabled?
      connection_db_config.configuration_hash[:track_gtid]
    end

    def self.production_schema_name
      self.cluster_name.to_s.underscore
    end

    def self.cluster_names
      [cluster_name]
    end

    def cluster_names
      self.class.cluster_names
    end

    def self.cluster_name
      return @cluster_name if defined?(@cluster_name)

      @cluster_name = ancestors.find do |ancestor|
        ancestor.is_a?(Class) && ancestor.superclass == ApplicationRecord::Base
      end&.name&.demodulize.underscore.to_sym
    end

    def cluster_name
      self.class.cluster_name
    end

    def self.throttler_cluster_names
      [throttler_cluster_name]
    end

    def throttler_cluster_names
      self.class.throttler_cluster_names
    end

    def self.throttler_cluster_name
      cluster_name
    end

    def throttler_cluster_name
      self.class.throttler_cluster_name
    end

    # Override in cluster subclass to run `DestroyDependentRecordsJob` jobs in a dedicated queue.
    def self.dedicated_background_destroy_queue_name
    end

    def self.default_github_sql_options
      {}
    end

    # rubocop:disable GitHub/NoGitHubSql
    def self.github_sql
      GitHubSQLBuilder.new(connection, default_github_sql_options)
    end

    def github_sql
      self.class.github_sql
    end

    def self.github_sql_descending_batched_between(start:, finish:, batch_size: 1000)
      GitHub::SQL::DescendingBatchedBetween.new(start: start, finish: finish, batch_size: batch_size, query_builder: github_sql) # rubocop:disable GitHub/DoNotCallMethodsOnGitHubSQLDescendingBatchedBetween
    end

    def self.github_sql_batched_between(start:, finish:, batch_size: 1000)
      GitHub::SQL::BatchedBetween.new(start: start, finish: finish, batch_size: batch_size, query_builder: github_sql) # rubocop:disable GitHub/DoNotCallMethodsOnGitHubSQLBatchedBetween
    end

    def self.github_sql_batched(start: 0, limit: 1000)
      GitHub::SQL::Batched.new(start: start, limit: limit, query_builder: github_sql) # rubocop:disable GitHub/DoNotCallMethodsOnGitHubSQLBatched
    end

    def self.batched_sql_builder(start: 0, limit: 1000)
      GitHub::SQL::BatchedBuilder.new(start: start, limit: limit, connection: connection)
    end
    # rubocop:enable GitHub/NoGitHubSql

    # Returns the current replication wait time in milliseconds.
    #
    # This can be used to determine whether a write query that happened
    # at a specific time in the past can be safely read from a replica.
    def self.default_replication_wait!
      delay = throttler_cluster_names.map do |name|
        Freno.client.replication_delay(store_name: name)
      end
      delay.max * 1000 + 100
    end

    def self.default_replication_wait
      default_replication_wait!
    rescue Freno::Error => e
      Failbot.report(e) if GitHub.environment.fetch("GH_FRENO_UNAVAILABLE", 0) == 0
      DEFAULT_REPLICATION_WAIT_TIME_MILLIS
    end

    def self.default_live_updates_wait
      default_replication_wait
    end

    def self.encrypts(*attributes, key_provider: nil, key: nil, deterministic: false, support_unencrypted_data: nil, downcase: false, ignore_case: false, previous: [], **context_properties)
      # Validate encryption is only happening on one attribute
      # the call to `.sole` will also raise similar errors
      # but it's probably better to be explicit here
      raise "Expected an attribute for encryption" if attributes.length < 1
      raise "GitHub only supports encrypting a single attribute at a time" if attributes.length > 1

      # pull out the sole attribute
      attribute = attributes.sole

      # Ensure only a GitHubKeyProvider is used (we allow a custom one for if the table/attribute name change)
      if !key_provider.nil? && !key_provider.instance_of?(GitHub::Encryption::GitHubKeyProvider)
        raise "A GitHub::Encryption::GitHubKeyProvider must be used"
      end

      # If no key provider is set, instanciate one
      kp = key_provider || GitHub::Encryption::GitHubKeyProvider.new(table: table_name.to_sym, attribute: attribute)

      if !(previous.nil? || previous.empty?)
        raise "A GitHub::Encryption::GitHubPreviousEncryptor must be used for the previous argument"
      end

      github_previous = [{
        key_provider: GitHub::Encryption::NoOpKeyProvider.new,
        encryptor: GitHub::Encryption::GitHubPreviousEncryptor.new(table: table_name.to_sym, attribute: attribute)
      }]

      # call to rails encryption
      super(attribute, key_provider: kp, previous: github_previous, key: nil, deterministic: false, support_unencrypted_data: nil, downcase: false, ignore_case: false, **context_properties)

      self.decorate_attributes([attribute]) do |attribute_name, cast_type|
        scheme = scheme_for key_provider: key_provider, key: key, deterministic: deterministic, support_unencrypted_data: support_unencrypted_data, \
          downcase: downcase, ignore_case: ignore_case, previous: previous, **context_properties

        GitHub::Encryption::FeatureFlagEncryptedType.new(scheme:, cast_type:, attribute_name:, model_name: self.name, table_name: table_name.to_sym)
      end
    end

    def default_live_updates_wait
      # We only want to memoize this this value in single instances.
      # Never move this memoization into the class level method.
      @live_updates_wait ||= begin
        self.class.default_live_updates_wait
      end
    end

    def serializable_hash(options = nil)
      guard_against_unsafe_serialization("serializable_hash", options)

      super
    end

    def as_json(options = nil)
      guard_against_unsafe_serialization("as_json", options)

      super
    end

    def self.with_read(&block)
      ActiveRecord::Base.connected_to(role: :reading, &block)
    end

    def with_read(&block)
      self.class.with_read(&block)
    end

    def self.with_write(&block)
      ActiveRecord::Base.connected_to(role: :writing, &block)
    end

    def with_write(&block)
      self.class.with_write(&block)
    end

    class UnsafeSerializationError < ArgumentError; end

    private

    def guard_against_unsafe_serialization(method_name, options = nil)
      safe_serialization = options.present? && (options[:dangerously_allow_all_keys] == true || !(options[:only] || []).empty?)

      return if safe_serialization

      exception = UnsafeSerializationError.new("#{method_name} called on #{self.class} without :only option. You must explicitly declare the keys you wish to serialize")
      exception.set_backtrace(caller)
      Failbot.report(exception)

      if Rails.env.test? || Rails.env.development?
        raise exception
      end
    end
  end
end
