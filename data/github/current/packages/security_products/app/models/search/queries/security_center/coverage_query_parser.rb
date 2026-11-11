# typed: strict
# frozen_string_literal: true

module Search
  module Queries
    module SecurityCenter
      class CoverageQueryParser

        QUALIFIERS = T.let([
          (ADVANCED_SECURITY = :"advanced-security"),
          (ARCHIVED = :archived),
          (CODE_SCANNING = :"code-scanning-alerts"),
          (CODE_SCANNING_PR_ALERTS = :"code-scanning-pull-request-alerts"),
          (CODE_SCANNING_DEFAULT_SETUP = :"code-scanning-default-setup"),
          (DEPENDABOT_ALERTS = :"dependabot-alerts"),
          (DEPENDABOT_SECURITY_UPDATES = :"dependabot-security-updates"),
          (VISIBILITY = :is),
          (REPOSITORY = :repo),
          (SECRET_SCANNING = :"secret-scanning-alerts"),
          (SECRET_SCANNING_PUSH_PROTECTION = :"secret-scanning-push-protection"),
          (SORT = :sort),
          (TEAM = :team),
          (TOPIC = :topic),
          (PROPERTIES = Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT),
          (OWNER = :owner),
          (OWNER_TYPE = :"owner-type")
        ].freeze, T::Array[T.any(Symbol, String)])

        sig { returns(T.class_of(Base)) }; attr_reader :parser
        sig { returns(String) }; attr_reader :query_string

        sig { params(query_string: String).void }
        def initialize(query_string)
          @parser = T.let(Base.new_parser(QUALIFIERS), T.class_of(Base))
          @query_string = T.let(query_string, String)
        end

        sig { returns(T::Array[Symbol]) }
        def used_qualifiers
          parser.parse(query_string).keys
        end

        sig { returns(String) }
        def canonicalize
          parser.canonicalize(query_string)
        end

        sig { params(qualifier: Symbol, value: String).returns(String) }
        def add_or_replace(qualifier, value)
          parser.add_or_replace(query_string, qualifier, value)
        end

        sig { params(qualifier: Symbol, value: String).returns(String) }
        def add_or_remove(qualifier, value)
          parser.add_or_remove(query_string, qualifier, value)
        end

        sig { params(qualifier: Symbol, value: String).returns(T::Boolean) }
        def pair_exists?(qualifier, value)
          parser.pair_exists?(query_string, qualifier, value)
        end

        sig { params(qualifier: Symbol).returns(T::Boolean) }
        def qualifier_exists?(qualifier)
          parser.qualifier_exists?(query_string, qualifier)
        end

        sig { params(qualifiers: T::Array[Symbol]).returns(T::Boolean) }
        def any_qualifiers_exist?(qualifiers)
          parser.any_qualifiers_exist?(query_string, qualifiers)
        end

        sig { params(qualifiers: T::Array[Symbol]).returns(String) }
        def remove_qualifiers(qualifiers)
          parser.remove_qualifiers(query_string, qualifiers)
        end

        sig { params(qualifier: Symbol).returns([T::Array[String], T::Array[String]]) }
        def values_for_qualifier(qualifier)
          [
            parser.get_qualified_values(query_string, qualifier),
            parser.get_qualified_values(query_string, parser.negate_qualifier(qualifier))
          ]
        end

        sig { returns([T::Array[String], T::Array[String]]) }
        def values_without_qualifiers
          negation_literal = "NOT"
          values = parser.get_unqualified_values(query_string)
          literals = values.join(" ").scan(/(?:#{negation_literal}\s)?[\w\/,-]+/)
          neg, pos = literals.partition { |l| l.start_with?(negation_literal) }

          [
            pos.flat_map { |l| l.split(",") },
            neg.flat_map { |l| l.gsub("#{negation_literal} ", "").split(",") }
          ]
        end

        sig { returns(String) }
        def custom_properties_query_string
          parsed_query = @parser.parse(query_string)
          parsed_query = parsed_query.select do |qualifier|
            qualifier.match?(Search::Queries::RepoQuery::PROPERTIES_PREFIXED_REGEX_TEXT)
          end
          @parser.to_s(parsed_query)
        end

        sig { returns([T.nilable(String), T.nilable(String)]) }
        def sort_by
          field = parser.get_qualified_values(query_string, SORT).join
          desc = !!field.slice!("-desc")
          asc = (field.slice!("-asc") && !desc)
          direction =
            if desc
              "desc"
            elsif asc
              "asc"
            end

          field = nil if field.blank?
          [field, direction]
        end

        sig { returns(T::Boolean) }
        def has_filter_by_status?
          [
            values_for_qualifier(CODE_SCANNING),
            values_for_qualifier(CODE_SCANNING_PR_ALERTS),
            values_for_qualifier(CODE_SCANNING_DEFAULT_SETUP),
            values_for_qualifier(DEPENDABOT_ALERTS),
            values_for_qualifier(DEPENDABOT_SECURITY_UPDATES),
            values_for_qualifier(SECRET_SCANNING),
            values_for_qualifier(SECRET_SCANNING_PUSH_PROTECTION),
          ].flatten.any?
        end
      end
    end
  end
end
