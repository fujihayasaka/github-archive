# typed: true
# frozen_string_literal: true

# Sharding
#
# The sharding module can be used with database tables that are backed by
# a sharding layer (like Vitess) and therefore require the presence of a
# sharding key with queries.
#
# The module allows setting an attribute name as the sharding key. This will
# add the sharding key to any single record queries triggered by methods
# like `save`, `update`, `reload`, etc.
#
# Here's an example how to use it:
#
#     class CheckSuite < ApplicationRecord::Domain::RepositoriesActionsChecks
#       include Checks::RepositorySharding
#
#       configure_sharding(should_shard: -> (record, operation) {
#         # return a boolean value
#         [:reload, :save, :save!].include?(operation)
#       })
#     end
#
# This will add `repository_id = N` to queries that reload, update, or destroy
# any record of this class. Example:
#
#     check_suite = CheckSuite.where(repository_id: repository.id).first
#     check_suite.update(name: "foobar")
#     # => `UPDATE ... WHERE check_suite.id = X AND check_suite.repository_id = Y`
#     check_suite.destroy
#     # => `DELETE ... WHERE check_suite.id = X AND check_suite.repository_id = Y`
#
# The sharding key clause helps to route the query to the right shard with
# minimal overhead and therefore optimal performance.
module Checks
  module RepositorySharding
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { ActiveRecord::Base }

    class_methods do
      def configure_sharding(should_shard:)
        @should_shard = should_shard
      end

      def should_shard
        @should_shard
      end
    end

    def reload(*, **)
      with_sharding(:reload) { super }
    end

    # also covers `update`, `update_attribute`, `toggle!`
    def save(*, **)
      with_sharding(:save) { super }
    end

    # also covers `update!`
    def save!(*, **)
      with_sharding(:save!) { super }
    end

    # also covers `update_column`
    def update_columns(*, **)
      with_sharding(:update_columns) { super }
    end

    def touch(*, **)
      with_sharding(:touch) { super }
    end

    # also covers `decrement!`
    def increment!(*, **)
      with_sharding(:increment!) { super }
    end

    # also covers `destroy!`
    def destroy(*, **)
      with_sharding(:destroy) { super }
    end

    def delete(*, **)
      with_sharding(:delete) { super }
    end

    private

    def with_sharding(operation)
      # Work around https://github.com/sorbet/sorbet/issues/4182
      klass = T.cast(self.class, T.all(T.class_of(ActiveRecord::Base), RepositorySharding::ClassMethods))

      should_shard = klass.should_shard

      raise ArgumentError.new("should_shard needs to be configured") if should_shard.blank?
      raise ArgumentError.new("column 'repository_id' has to exist") unless has_attribute?(:repository_id)

      sharding_key_enabled = should_shard.call(self, operation)
      stats_tags = ["operation:#{operation}", "sharding_key_enabled:#{sharding_key_enabled}", "persisted:#{self.persisted?}"]

      GitHub.dogstats.time("#{T.must(klass.name).underscore}.with_sharding_duration", tags: stats_tags) do
        if sharding_key_enabled
          # Make sure sharding key isn't `NULL` when the record isn't persisted, yet
          value = self.persisted? ? attribute_in_database(:repository_id) : self.public_send(:repository_id)

          klass.where(repository_id: value).scoping(all_queries: true) do
            yield
          end
        else
          yield
        end
      end
    end
  end
end
