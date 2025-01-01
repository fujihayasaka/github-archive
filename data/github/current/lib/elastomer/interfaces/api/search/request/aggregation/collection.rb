# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Api
      module Search
        module Request
          module Aggregation
            class Collection
              # This struct collects 1 or more aggregations into an array and then serializes them into a hash with keys
              # derived from the Aggregation slugs. This serialized hash is then suitable for inclusion in an Elasticsearch
              # request, keyed by "aggregations". For example:
              #
              # my_aggregation_collection = Aggregation::Collection.new(aggregations: [
              #  Aggregation::Terms.new(slug: :my_terms, field: "my_field")
              #  Aggregation::Filter.new(slug: :my_filter, filter: { term: { my_field: "my_value" } })
              # ])
              #
              # my_aggregation_collection.to_hash # => { my_terms: {...}, my_filter: {...} }
              extend T::Sig

              sig { returns(T::Array[Aggregatable]) }
              attr_reader :aggregations

              sig do
                params(aggregations: T::Array[Aggregatable])
                .void
              end
              def initialize(aggregations = [])
                @aggregations = aggregations
              end

              # Add an aggregation object to the top-level collection. Note that this does not handle sub-aggregations.
              # If you want to add a sub-aggregation to an existing aggregation, you must add it directly to that aggregation.
              sig { params(aggregation: Aggregatable).void }
              def push(aggregation)
                raise ArgumentError if duplicate_slugs?([aggregation])
                @aggregations.push(aggregation)
              end

              sig { params(aggregation_collection: Aggregation::Collection).void }
              def concat(aggregation_collection)
                raise ArgumentError if duplicate_slugs?(aggregation_collection.aggregations)
                @aggregations.concat(aggregation_collection.aggregations)
              end

              sig { returns(T::Hash[Symbol, T.untyped]) }
              def to_hash
                # Convert the array of aggregations into a hash with the aggregation slugs as keys
                @aggregations.each_with_object({}) do |aggregation, hash|
                  hash.merge!(aggregation.to_hash)
                end
              end

              sig { params(new_aggregations: T::Array[Aggregatable]).returns(T::Boolean) }
              private def duplicate_slugs?(new_aggregations)
                new_slugs = new_aggregations.map(&:slug)
                existing_slugs = @aggregations.map(&:slug)
                (new_slugs & existing_slugs).any?
              end
            end
          end
        end
      end
    end
  end
end
