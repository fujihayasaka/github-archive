# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveIprDefaultToDraftKvValues < MoveKeyValuesBase
      DefaultToDraftKeyTransformer = PullRequests::KV::KeyTransformer.new(
        old_key_pattern: %r(
          \Auser
          \.pull_requests
          \.default_to_draft
          \.(?<user_id>\d+)
          -(?<repository_id>\d+)
          \z
        )x,
        new_key_template: "pull_requests/default_to_draft/user%{user_id}"
      )

      class IprKeyValues < ApplicationRecord::Domain::IssuesPullRequests
        self.table_name = :ipr_key_values
      end

      sig { override.returns(T.class_of(ApplicationRecord::Base)) }
      def model_class
        IprKeyValues
      end

      sig { override.returns(T::Array[String]) }
      def insert_fields = %w[key repository_id value created_at updated_at expires_at]

      sig { override.params(rows: T::Array[T::Hash[Symbol, T.anything]]).returns(T::Array[T.anything]) }
      def insert_values(rows)
        transformer = DefaultToDraftKeyTransformer
        rows.map do |row|
          transformer.new_key_and_repo_id(T.cast(row[:key], String)) +
            row.values_at(:value, :created_at, :updated_at, :expires_at)
        end
      end

      iterate_key_values [
        "user.pull_requests.default_to_draft.%"
      ]
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::MoveIprDefaultToDraftKvValues.new(args).run
end
