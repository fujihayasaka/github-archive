# typed: strict
# frozen_string_literal: true

require "date"

module Search
  module Queries
    # Parses and normalizes the `q` query parameter for the artifact registry
    # list endpoint. Extends SecurityCenter::Base to reuse the standard
    # qualifier tokenisation, negation handling, and comma-separated value
    # parsing used across the security center controllers.
    class ArtifactRegistryQuery < Search::Queries::SecurityCenter::Base
      include DateMacroHelper

      QUALIFIER_SORT = :sort
      QUALIFIER_ARTIFACT_REGISTRY = :"artifact-registry"
      QUALIFIER_RUNTIME_RISK = :"runtime-risk"
      QUALIFIER_ARTIFACT_REGISTRY_URL = :"artifact-registry-url"
      QUALIFIER_HAS = :has
      QUALIFIER_CREATED = :created
      QUALIFIER_UPDATED = :updated

      QUALIFIERS = T.let([
        QUALIFIER_SORT,
        QUALIFIER_ARTIFACT_REGISTRY,
        QUALIFIER_RUNTIME_RISK,
        QUALIFIER_ARTIFACT_REGISTRY_URL,
        QUALIFIER_HAS,
        QUALIFIER_CREATED,
        QUALIFIER_UPDATED,
      ].freeze, T::Array[Symbol])

      SORT_MAPPING = T.let({
        "created-desc" => "created-desc",
        "created-asc" => "created-asc",
        "updated-desc" => "updated-desc",
        "updated-asc" => "updated-asc",
      }.freeze, T::Hash[String, String])

      VALID_SOURCE_REGISTRIES = T.let(%w[jfrog-artifactory].freeze, T::Array[String])
      VALID_RUNTIME_RISKS = T.let(%w[critical-resource internet-exposed sensitive-data lateral-movement].freeze, T::Array[String])
      VALID_HAS_VALUES = T.let(%w[deployments].freeze, T::Array[String])

      DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/

      class << self
        # Parses the raw query string into a normalized hash suitable for
        # building model-layer filters.
        #
        # Returns a hash with keys like:
        #   :sort, :search_text,
        #   :"artifact-registry", :"-artifact-registry",
        #   :"runtime-risk", :"-runtime-risk",
        #   :has, :"-has",
        #   :created, :updated  (parsed into operator hashes)
        #   :filters (structured hash for ArtifactMetadata.apply_filters)
        sig { params(query_string: String, timezone: T.nilable(ActiveSupport::TimeZone)).returns(T::Hash[Symbol, T.untyped]) }
        def parse_and_normalize(query_string, timezone: nil)
          # Resolve @today macros before parsing
          resolved = new_instance.replace_today_macro(query_string, timezone: timezone)

          hash = parse(resolved)

          result = {}

          # Extract free-text search (everything not a qualifier)
          if hash[literals_key].present?
            result[:search_text] = hash[literals_key].join(" ")
          end

          # Normalize sort
          if hash[QUALIFIER_SORT].present?
            sort_value = hash[QUALIFIER_SORT].first&.downcase
            result[:sort] = SORT_MAPPING[sort_value]
          end

          # Build structured filters hash for the model layer
          result[:filters] = build_filters(hash)

          # Remove internal keys
          hash.delete(literals_key)

          result
        end

        protected

        sig { returns(T::Array[Symbol]) }
        def allowed_qualifiers
          QUALIFIERS
        end

        sig { returns(T::Boolean) }
        def preserve_case
          true
        end

        private

        sig { returns(ArtifactRegistryQuery) }
        def new_instance
          @_instance ||= T.let(new, T.nilable(ArtifactRegistryQuery))
        end

        sig { params(hash: T::Hash[T.any(String, Symbol), T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
        def build_filters(hash)
          filters = {}

          # artifact-registry (is / is not)
          apply_single_value_filter(filters, hash, QUALIFIER_ARTIFACT_REGISTRY,
            key: :source_registry, exclude_key: :exclude_source_registry,
            allowed: VALID_SOURCE_REGISTRIES)

          # runtime-risk (is one of / is not one of)
          apply_multi_value_filter(filters, hash, QUALIFIER_RUNTIME_RISK,
            key: :runtime_risks, exclude_key: :exclude_runtime_risks,
            allowed: VALID_RUNTIME_RISKS)

          # artifact-registry-url (is one of / is not one of)
          apply_multi_value_filter(filters, hash, QUALIFIER_ARTIFACT_REGISTRY_URL,
            key: :registry_urls, exclude_key: :exclude_registry_urls)

          # has (deployments) — normalize case so "has:DEPLOYMENTS" works the same as "has:deployments"
          has_values = Array(hash[QUALIFIER_HAS]).map(&:downcase).select { |v| VALID_HAS_VALUES.include?(v) }
          filters[:has_deployments] = true if has_values.include?("deployments")

          negated_has = Array(hash[negate_qualifier(QUALIFIER_HAS)]).map(&:downcase).select { |v| VALID_HAS_VALUES.include?(v) }
          filters[:exclude_has_deployments] = true if negated_has.include?("deployments")

          # created / updated date filters
          parse_date_qualifier(filters, hash, QUALIFIER_CREATED, :created)
          parse_date_qualifier(filters, hash, QUALIFIER_UPDATED, :updated)

          filters
        end

        sig do
          params(
            filters: T::Hash[Symbol, T.untyped],
            hash: T::Hash[T.any(String, Symbol), T.untyped],
            qualifier: Symbol,
            key: Symbol,
            exclude_key: Symbol,
            allowed: T.nilable(T::Array[String]),
          ).void
        end
        def apply_single_value_filter(filters, hash, qualifier, key:, exclude_key:, allowed: nil)
          values = Array(hash[qualifier])
          value = values.first
          # Normalize case for enum qualifiers (those with an allowed list) so
          # callers can use any casing (e.g. "JFROG-Artifactory").  URL qualifiers
          # have no allowed list and are left as-is to preserve their original case.
          normalized = allowed ? value&.downcase : value
          if normalized.present? && (allowed.nil? || allowed.include?(normalized))
            filters[key] = normalized
          end

          neg_values = Array(hash[negate_qualifier(qualifier)])
          neg_value = neg_values.first
          normalized_neg = allowed ? neg_value&.downcase : neg_value
          if normalized_neg.present? && (allowed.nil? || allowed.include?(normalized_neg))
            filters[exclude_key] = normalized_neg
          end
        end

        sig do
          params(
            filters: T::Hash[Symbol, T.untyped],
            hash: T::Hash[T.any(String, Symbol), T.untyped],
            qualifier: Symbol,
            key: Symbol,
            exclude_key: Symbol,
            allowed: T.nilable(T::Array[String]),
          ).void
        end
        def apply_multi_value_filter(filters, hash, qualifier, key:, exclude_key:, allowed: nil)
          values = Array(hash[qualifier])
          # Normalize case for enum qualifiers (those with an allowed list) so
          # callers can use any casing.  URL qualifiers have no allowed list and
          # are left as-is to preserve their original case.
          values = values.map(&:downcase) if allowed
          values = values.select { |v| allowed.include?(v) } if allowed
          filters[key] = values if values.any?

          neg_values = Array(hash[negate_qualifier(qualifier)])
          neg_values = neg_values.map(&:downcase) if allowed
          neg_values = neg_values.select { |v| allowed.include?(v) } if allowed
          filters[exclude_key] = neg_values if neg_values.any?
        end

        sig do
          params(
            filters: T::Hash[Symbol, T.untyped],
            hash: T::Hash[T.any(String, Symbol), T.untyped],
            qualifier: Symbol,
            field: Symbol,
          ).void
        end
        def parse_date_qualifier(filters, hash, qualifier, field)
          # Positive date values (created:>=2025-01-01, created:2025-01-01..2025-06-01, etc.)
          values = Array(hash[qualifier])
          if values.any?
            parsed = parse_date_value(values.first)
            filters[field] = parsed if parsed
          end

          # Negated date values (exact date exclusion: -created:2025-01-01)
          neg_values = Array(hash[negate_qualifier(qualifier)])
          if neg_values.any?
            dates = neg_values.select { |d| valid_date?(d) }
            filters[field] = { operator: "is_not", value: dates } if dates.any?
          end
        end

        sig { params(value: T.nilable(String)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def parse_date_value(value)
          return nil if value.blank?

          if value.include?("..")
            parts = value.split("..", 2)
            start_date = parts[0]
            end_date = parts[1]
            return nil unless valid_date?(start_date) && valid_date?(end_date)
            { operator: "..", start: start_date, end: end_date }
          elsif value.start_with?(">=")
            date = value[2..]
            valid_date?(date) ? { operator: ">=", value: date } : nil
          elsif value.start_with?(">")
            date = value[1..]
            valid_date?(date) ? { operator: ">", value: date } : nil
          elsif value.start_with?("<=")
            date = value[2..]
            valid_date?(date) ? { operator: "<=", value: date } : nil
          elsif value.start_with?("<")
            date = value[1..]
            valid_date?(date) ? { operator: "<", value: date } : nil
          else
            # Exact date(s) — comma-separated for "is one of"
            dates = value.split(",").select { |d| valid_date?(d) }
            return nil if dates.empty?
            { operator: "is", value: dates }
          end
        end

        sig { params(str: T.nilable(String)).returns(T::Boolean) }
        def valid_date?(str)
          return false if str.blank?

          begin
            Date.iso8601(str.to_s)
            true
          rescue Date::Error
            false
          end
        end
      end

      # Instance is only created so class methods can call replace_today_macro
      sig { void }
      def initialize; end
    end
  end
end
