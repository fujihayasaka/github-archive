# typed: true
# frozen_string_literal: true

module Search
  module Queries
    module SecurityCenter
      class Base
        extend T::Sig
        include GitHub::Memoizer

        class << self
          def new_parser(allowed_qualifiers)
            Class.new(self) do
              define_singleton_method :allowed_qualifiers do
                allowed_qualifiers
              end
            end
          end

          def parse(query_string = "")
            ParsedQuery
              .parse(query_string, terms: allowed_qualifiers)
              .reduce({ literals_key => [] }) do |memo, component|
                # qualifier:value
                if component.kind_of?(Array)
                  qualifier, value, negated = component
                  next memo if value.nil?

                  qualifier = negate_qualifier(qualifier) if negated
                  value = convert_case_value(value, preserve_case)

                  memo[qualifier] ||= []
                  memo[qualifier] |= value.split(",")
                # Unqualified values (free-form search terms).
                elsif component.kind_of?(String)
                  memo[literals_key] |= component.split(" ")
                end

                memo
              end
              .with_indifferent_access
          end

          def canonicalize(query_string = "")
            parse(query_string)
              .sort_by { |qualifier, _| qualifier }
              .map do |qualifier, values|
                next if values.empty?
                values_string = values.sort.join(",")
                qualifier == literals_key ? values_string : "#{qualifier}:#{values_string}"
              end
              .compact
              .join(" ")
          end

          def add_or_remove(query_string = "", qualifier, value)
            parsed_query = parse(query_string)
            parsed_query[qualifier] ||= []

            if pair_exists?(query_string, qualifier, value)
              parsed_query[qualifier].delete(value)
            else
              value = convert_case_value(value, preserve_case)
              parsed_query[qualifier] << value
            end

            parsed_query.delete(qualifier) if parsed_query[qualifier].empty?

            to_s(parsed_query)
          end

          def add_or_replace(query_string = "", qualifier, value)
            parsed_query = parse(query_string)

            value = convert_case_value(value, preserve_case)
            parsed_query[qualifier] = [value]
            to_s(parsed_query)
          end

          def any_qualifiers_exist?(query_string = "", qualifiers = [])
            negated_qualifiers = qualifiers.map { |qualifier| negate_qualifier(qualifier) }
            qualifiers.any? { |qualifier| qualifier_exists?(query_string, qualifier) } ||
            negated_qualifiers.any? { |neg_qualifier| qualifier_exists?(query_string, neg_qualifier) }
          end

          def get_qualified_values(query_string = "", qualifier)
            parsed_query = parse(query_string)
            preserve_case ? (parsed_query[qualifier] || []) : (parsed_query[qualifier] || []).map(&:downcase)
          end

          def get_unqualified_values(query_string = "")
            parse(query_string)[literals_key]
          end

          def has_duplicate_qualifiers?(query_string = "")
            return false if query_string.blank?

            qualifiers = Set.new

            query_string.split(" ").each do |component|
              pair = component.split(separator, 2)

              # Ignore unqualified values.
              next if pair.length != 2

              return true if qualifiers.include? pair.first.downcase
              qualifiers << pair.first.downcase
            end

            false
          end

          def has_conflicting_values?(query_string = "")
            return false if query_string.blank?

            parsed_query = parse(query_string)
            parsed_query.each do |qualifier, values|
              next if qualifier == literals_key # skip unqualified values
              next if qualifier.start_with?(negated_qualifier_prefix) # skip negated qualifiers because we will have to encounter the positive version if there are conflicting values
              next if values.empty? # edge case: a query string like `secret-type:` produces an empty values array. We can't conflict when there's no values

              negated_values = parsed_query["#{negated_qualifier_prefix}#{qualifier}"] || []
              return true if (values.map(&:downcase) - negated_values.map(&:downcase)).empty?
            end

            false
          end

          # Whether or not the query string contains a qualifier without a value.
          #   For example, `is: sort:updated-at` contains a qualifier (`is`) without a value.
          def has_qualifiers_without_value?(query_string = "")
            parse(query_string).reject { |k| k == literals_key }.any? { |_, v| v.empty? }
          end

          def is_valid?(query_string = "")
            return true if query_string.blank?

            query_string.split(" ").each do |component|
              pair = component.split(separator, 2)

              return false if component.include?(separator) && pair.length != 2

              # Unqualified values are valid.
              next if pair.length < 2

              return false if pair.second.blank?

              matches = T.let(false, T::Boolean)
              allowed_qualifiers.each do |allowed_qualifier|
                qualifier = strip_negation(pair.first).downcase

                if allowed_qualifier.is_a?(Regexp) && qualifier.match?(allowed_qualifier)
                  matches = true
                  break
                elsif allowed_qualifier.is_a?(Symbol) && allowed_qualifier == qualifier.to_sym
                  matches = true
                  break
                end
              end

              return false unless matches
            end

            !has_duplicate_qualifiers?(query_string) && !has_conflicting_values?(query_string)
          end

          def pair_exists?(query_string = "", qualifier, value)
            parsed_query = parse(query_string)
            !!parsed_query[qualifier]&.include?(value)
          end

          def qualifier_exists?(query_string = "", qualifier)
            parsed_query = parse(query_string)
            parsed_query.key?(qualifier)
          end

          def query_string_for_url(query_string = "")
            return "?" if query_string.blank?

            "?query=#{CGI.escape(query_string)}"
          end

          def remove_qualifier(query_string = "", qualifier)
            parsed_query = parse(query_string)
            parsed_query.delete(qualifier)
            to_s(parsed_query)
          end

          def remove_qualifiers(query_string = "", qualifiers)
            parsed_query = parse(query_string)
            qualifiers.each { |qualifier| parsed_query.delete(qualifier) }
            to_s(parsed_query)
          end

          # Removes the qualifier if it exists with the given value (even if multiselect).
          # Otherwise adds or replaces the qualifier with the given value.
          def toggle_qualifier(query_string, qualifier, value)
            return remove_qualifier(query_string, qualifier) if get_qualified_values(query_string, qualifier).any? { |val| val.casecmp?(value) }
            add_or_replace(query_string, qualifier, value)
          end

          def to_s(parsed_query = {})
            parsed_query
              .reduce([]) do |query_strings, (qualifier, values)|
                if qualifier == literals_key
                  query_strings += values
                else
                  output_value = values.map { |value| ParsedQuery.encode_value(value.to_s) }.join(",")
                  query_strings << "#{qualifier}#{separator}#{output_value}"
                end

                query_strings
              end
              .join(" ")
          end

          def negate_qualifier(qualifier)
            return qualifier if qualifier.start_with?(negated_qualifier_prefix)

            negate = "#{negated_qualifier_prefix}#{qualifier}"

            qualifier.is_a?(String) ? negate : negate.to_sym
          end

          def literals_key
            "_literals"
          end

          protected

          def allowed_qualifiers
            raise NotImplementedError
          end

          def separator
            ":"
          end

          def preserve_case
            false
          end

          def convert_case_value(value, preserve_case)
            return value if preserve_case

            value.downcase
          end

          def strip_negation(value)
            return value unless value.start_with?(negated_qualifier_prefix)

            value.delete(negated_qualifier_prefix)
          end

          def negated_qualifier_prefix
            "-"
          end
        end
      end
    end
  end
end
