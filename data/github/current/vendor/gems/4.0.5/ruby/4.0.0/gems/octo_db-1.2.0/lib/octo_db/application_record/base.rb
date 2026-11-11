# typed: true
# frozen_string_literal: true

require "active_record"

module OctoDb::ApplicationRecord
  class Base < ActiveRecord::Base
    self.abstract_class = true

    extend OctoDb::LikeQuery

    # Scope for querying when a field does not match one of many possible values
    # You can use `where(field: [value1, value2])` as well, but when your array
    # is very large this performs better by avoiding Arel object allocations.
    scope :without_ids, ->(ids, field: "#{quoted_table_name}.#{quoted_primary_key}") { ids.any? ? where("#{field} NOT IN (?)", ids) : self }

    def self.scoped
      all
    end

    def self.gtid_tracking_enabled?
      connection_db_config.configuration_hash[:track_gtid]
    end

    def self.skip_gtid_check?
      false
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
        ancestor.is_a?(Class) && ancestor.superclass&.name == "ApplicationRecord::Base"
      end&.name&.demodulize&.underscore&.to_sym
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
  end
end
