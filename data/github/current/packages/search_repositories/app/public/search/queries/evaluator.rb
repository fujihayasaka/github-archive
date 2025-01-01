# typed: strict
# frozen_string_literal: true

module Search
  module Queries
    module Evaluator

      SUPPORTED_QUALIFIERS = T.let(%w(fork language visibility).freeze, T::Array[String])
      SUPPORTED_TERMS = T.let([
        *SUPPORTED_QUALIFIERS,
        Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT
      ].freeze, T::Array[String])

      ENUMERABLE_TERMS = T.let(["language", Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT].freeze, T::Array[String])

      sig { params(repo: ::Repository, query: String).returns(T::Boolean) }
      def self.evaluate!(repo, query)
        parsed_query = ::Search::ParsedQuery.parse(query, terms: SUPPORTED_TERMS, enumerable_terms: ENUMERABLE_TERMS)

        key_value_segments, raw_text_segments = parsed_query.partition { |segment| segment.is_a?(Array) }

        raise ArgumentError, "Unsupported query fragments: #{raw_text_segments.join(', ')}" if raw_text_segments.any?

        custom_properties_keys, repo_attribute_keys = key_value_segments
          .map { |key, _value, _negated| key.to_s }
          .partition { |key| custom_properties_key?(key) }

        custom_properties_values = custom_properties_keys.any? ? repo.custom_properties_effective_values : {}
        repo_attribute_values = repo_attribute_keys.any? ? repo_attribute_values(repo, repo_attribute_keys) : {}

        key_value_segments.all? do |key, value, negated|
          key = key.to_s

          properties = custom_properties_key?(key) ? custom_properties_values : repo_attribute_values
          property_name = custom_properties_key?(key) ? key.split(".").drop(1).join(".") : key

          evaluate_property_segment(properties, property_name, Array(value), negated)
        end
      end

      sig do
        params(
          properties: T::Hash[String, T.nilable(T.any(String, T::Array[String]))],
          name: String,
          values: T::Array[String],
          negated: T.nilable(T::Boolean)
        ).returns(T::Boolean)
      end
      private_class_method def self.evaluate_property_segment(properties, name, values, negated)
        intersection = Array(properties[name]).map(&:downcase) & values.map(&:downcase)
        negated ? intersection.empty? : intersection.any?
      end

      sig { params(repo: ::Repository, keys: T::Array[String]).returns(T::Hash[String, T.nilable(T.any(String, T::Array[String]))])   }
      private_class_method def self.repo_attribute_values(repo, keys)
        keys
          .each_with_object({}) do |key, hash|
            if key == "fork"
              hash[key] = repo.fork?.to_s
            elsif key == "visibility"
              hash[key] = repo.visibility
            elsif key == "language"
              hash[key] = repo.primary_language&.name
            end
          end
      end

      sig { params(key: String).returns(T::Boolean) }
      private_class_method def self.custom_properties_key?(key)
        Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX.match(key).present?
      end
    end
  end
end
