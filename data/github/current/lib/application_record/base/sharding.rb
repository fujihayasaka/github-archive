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
#       include ApplicationRecord::Sharding
#
#       configure_sharding(sharding_key: :repository_id, should_shard: -> (record, operation) {
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
module ApplicationRecord
  module Sharding
    extend T::Helpers

    requires_ancestor { ActiveRecord::Base }

    module ClassMethods
      extend T::Helpers

      requires_ancestor { T.class_of(ActiveRecord::Base) }

      def configure_sharding(sharding_key:, should_shard: -> (_, _) { true })
        @sharding_key = sharding_key
        @should_shard = should_shard
      end

      def sharding_key
        @sharding_key
      end

      def should_shard
        @should_shard
      end
    end

    mixes_in_class_methods(ClassMethods)

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
      klass = T.cast(self.class, T.all(T.class_of(ActiveRecord::Base), Sharding::ClassMethods))

      should_shard = klass.should_shard
      sharding_key = klass.sharding_key

      # If sharding_key is nil, we don't need to do anything since `configure_sharding` was never called
      return yield if sharding_key.nil?

      raise ArgumentError.new("column '#{sharding_key}' has to exist") unless has_attribute?(sharding_key)

      sharding_key_enabled = should_shard.call(self, operation)
      stats_tags = ["operation:#{operation}", "sharding_key_enabled:#{sharding_key_enabled}", "persisted:#{self.persisted?}"]

      GitHub.dogstats.time("#{klass.name&.underscore}.with_sharding_duration", tags: stats_tags) do
        if sharding_key_enabled
          GitHub.logger.info("Using sharding key `#{sharding_key}`", { "code.namespace" => klass.name, "code.function" => "with_sharding" })
          # Make sure sharding key isn't `NULL` when the record isn't persisted, yet
          value = self.persisted? ? attribute_in_database(sharding_key) : self.public_send(sharding_key)

          return yield if value.nil?

          klass.where(sharding_key => value).scoping(all_queries: true) do
            yield
          end
        else
          yield
        end
      end
    end
  end
end
