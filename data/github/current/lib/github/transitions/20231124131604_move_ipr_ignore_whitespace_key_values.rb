# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"
require "github/transitions/move_key_values_base"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class MoveIprIgnoreWhitespaceKeyValues < MoveKeyValuesBase
      IgnoreWhitespaceKeyTransformer = PullRequests::KV::KeyTransformer.new(
        old_key_pattern: %r(
          \Auser_(?<user_id>\d+)
          \.repo_(?<repository_id>\d+)
          \.pull_request_(?<pr_number>\d+)
          \.ignore_whitespace
          \z
        )x,
        new_key_template: "pull_requests/ignore_whitespace/user%{user_id}.pr%{pr_number}",
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
        transformer = IgnoreWhitespaceKeyTransformer
        rows.map do |row|
          transformer.new_key_and_repo_id(T.cast(row[:key], String)) +
            row.values_at(:value, :created_at, :updated_at, :expires_at)
        end
      end

      iterate_key_values [
        "%.ignore_whitespace",
      ]
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(cleanup))

  GitHub::Transitions::MoveIprIgnoreWhitespaceKeyValues.new(args).run
end
