# typed: true
# frozen_string_literal: true

module Search
  class ParsletQuery
    extend T::Sig

    REPO_MENTION_PATTERN = /(?:^|\s)(-?)@([\w\-]+\/[\w\-.]+)(?=\s|$)/
    USER_MENTION_PATTERN = /(?:^|\s)(-?)@([\w\-]+)(?=\s|$)/

    sig { returns(String) }
    attr_reader :query

    sig { returns(T::Hash[Symbol, ::Search::ParsedQuery::BoolCollection]) }
    attr_reader :qualifiers

    sig { returns(BoolQualifier) }
    attr_reader :conditional_qualifiers

    sig { returns(T::Array[Qualifier]) }
    attr_reader :ownership_qualifiers

    sig { returns(T::Hash[Symbol, ::Search::ParsedQuery::BoolCollection]) }
    attr_reader :aggregation_qualifiers

    sig { returns(T.nilable(IndexType)) }
    attr_reader :index_type

    class Qualifier < T::Struct
      extend T::Sig

      const :field, Symbol
      const :collection, ::Search::ParsedQuery::BoolCollection

      sig { params(other: Qualifier).returns(T::Boolean) }
      def ==(other)
        self.field == other.field && self.collection == other.collection
      end
    end

    class QueryQualifier < T::Struct
      extend T::Sig

      const :query, String

      sig { params(other: QueryQualifier).returns(T::Boolean) }
      def ==(other)
        self.query == other.query
      end
    end

    class BoolQualifier < T::Struct
      extend T::Sig

      const :type, Symbol
      const :qualifiers, T::Array[T.any(Qualifier, BoolQualifier, QueryQualifier)]

      sig { params(other: BoolQualifier).returns(T::Boolean) }
      def ==(other)
        self.type == other.type && self.qualifiers == other.qualifiers
      end
    end

    class IndexType < T::Enum
      extend T::Sig

      enums do
        Issue = new
        PullRequest = new
      end
    end

    # Create a new ParsletQuery.
    #
    # phrase - The raw search phrase as a String
    # terms - The list of accepted filter terms (e.g., is, type, status, label)
    # current_user - The logged in user that entered the search
    # no_value_fields - The list of fields that support the "no:<field>" syntax
    # is_qualifier_map - The map of values supplied in an `is:` filter to their corresponding field names and values
    # enumerable_terms - The list of fields that support comma separated filter values
    # ownership_fields -
    # aggregation_fields - The list of fields that may be used to perform aggregations in ElasticSearch
    sig do
      params(
        phrase: String,
        terms: T::Array[Symbol],
        current_user: T.nilable(User),
        no_value_fields: T::Hash[Symbol, Symbol],
        is_qualifier_map: T::Hash[Symbol, T::Hash[Symbol, T.any(String, Symbol, T::Boolean)]],
        enumerable_terms: T::Array[Symbol],
        ownership_fields: T::Array[Symbol],
        aggregation_fields: T::Array[Symbol],
      ).void
    end
    def initialize(phrase, terms = [], current_user: nil, no_value_fields: {}, is_qualifier_map: {}, enumerable_terms: [], ownership_fields: [], aggregation_fields: [])
      @phrase = phrase.to_s.strip
      @no_value_fields = no_value_fields
      @is_qualifier_map = is_qualifier_map
      @current_user = current_user
      @terms = terms.flatten.uniq
      @enumerable_terms = enumerable_terms
      @ownership_fields = ownership_fields
      @aggregation_fields = aggregation_fields

      @qualifier_count = 0
      @qualifiers = Hash.new { |h, k| h[k] = ::Search::ParsedQuery::BoolCollection.new(k) }
      @conditional_qualifiers = nil
      @ownership_qualifiers = []
      @aggregation_qualifiers = Hash.new { |h, k| h[k] = ::Search::ParsedQuery::BoolCollection.new(k) }
      @query_parts = []
      @query = ""
      @index_type = nil
      @type_searches = []
      @issue_or_pr_searches = []
      @linked_searches = []
      @issues_index = %w(issue issues)
      @prs_index = %w(pr pull-request)
      @pr_fields = %w(merged queued draft)
      @issues_and_pr_fields = %w(open closed locked unlocked public private)
      @complex = false

      parse
    end

    def parse
      @query_parts = []
      @qualifier_count = 0

      parser_result = ::Search::Parsers::IssuesParser.new.parse(@phrase)
      parsed_tree = ::Search::Parsers::IssuesTransformer.new.apply(parser_result)
      parsed = parsed_tree[:root] #the root hash will only have one key:value pair for non-blank queries

      if parsed.is_a?(Hash)
        processed_qualifiers = process_qualifiers(parsed)

        if processed_qualifiers.nil?
          @conditional_qualifiers = BoolQualifier.new(type: :and, qualifiers: [])
        elsif !processed_qualifiers.is_a?(BoolQualifier)
          @conditional_qualifiers = BoolQualifier.new(type: :and, qualifiers: [processed_qualifiers])
        else
          @conditional_qualifiers = processed_qualifiers
        end
      else
        @conditional_qualifiers = BoolQualifier.new(type: :and, qualifiers: [])
      end

      GitHub.dogstats.distribution("search.advanced_search.qualifier_count", @qualifier_count)

      @index_type = assign_index_type
      @query = @query_parts.join(" ")
      @is_valid = true
    rescue Parslet::ParseFailed => failure
      STDERR.puts(failure.parse_failure_cause.ascii_tree) if $console
      GitHub.dogstats.increment("search.advanced_search.parslet_failed")
      GitHub.logger.info("Parslet failed to parse query",
        "exception.message" => failure.message,
        "gh.issues_advanced_search.query" => @phrase,
      )
      @is_valid = false
    end

    ## Identify the terms of a search and process then accordingly
    sig { params(parsed: T::Hash[Symbol, T.untyped]).returns(T.any(NilClass, Qualifier, BoolQualifier, QueryQualifier)) }
    def process_qualifiers(parsed)
      if parsed.has_key?(:filter_term)
        process_attribute(parsed[:filter_term])
      elsif parsed.has_key?(:text_term)
        expand_text_term_mentions_to_filters(parsed[:text_term].to_s)
      elsif parsed.has_key?(:or)
        @complex = true
        process_subtree(:or, parsed)
      elsif parsed.has_key?(:and)
        process_subtree(:and, parsed)
      end
    end

    ## Process text terms that are mentions and turn them into filters:
    # (legacy compatibility)
    # - repo_mention: @{user_name}/{repo_name}
    #                 -@{user_name}/{repo_name}
    # - user_mention: @{user_name}
    #                 -@{user_name}
    sig { params(query: String).returns(T.any(T.nilable(Qualifier), QueryQualifier)) }
    def expand_text_term_mentions_to_filters(query)
      if res = query.match(REPO_MENTION_PATTERN)
        return process_attribute({
          attribute: :repo,
          value: [res[2]],
          negative: res[1],
        })
      elsif res = query.match(USER_MENTION_PATTERN)
        return process_attribute({
          attribute: :user,
          value: [res[2]],
          negative: res[1],
        })
      end

      @query_parts << query
      QueryQualifier.new(query: query)
    end

    ## Process AND and OR operators
    sig { params(key: Symbol, side: T::Hash[Symbol, T.untyped]).returns(T.any(NilClass, Qualifier, BoolQualifier, QueryQualifier)) }
    def process_subtree(key, side)
      expression_terms = side[key]
      return unless expression_terms.is_a?(Array)

      qualifiers = expression_terms.map { |term| process_qualifiers(term) }.compact

      return qualifiers.first if qualifiers.length == 1

      BoolQualifier.new(type: key, qualifiers: qualifiers) if qualifiers.length > 0
    end

    ## Process filter terms
    sig { params(filter_term: Hash).returns(T.nilable(Qualifier)) }
    def process_attribute(filter_term)
      attribute_name = filter_term[:attribute].to_sym
      attribute_negative = filter_term[:negative]
      attribute_missing = filter_term[:missing]

      return unless @terms.include?(attribute_name) || @no_value_fields.include?(attribute_name)
      GitHub.dogstats.increment("search.advanced_search.qualifier", tags: ["field:#{attribute_name}"])
      @qualifier_count += 1

      attribute_value = preprocess_filter_value(filter_term)

      if attribute_name == :state && %w(merged draft).include?(attribute_value)
        attribute_name = :is
      end

      if attribute_name == :is
        # Some functions used by ConditionalIssueQuery (such as repository filter and some helper functions) expect
        # the `is` qualifier to be set along with the mapped value. So even though we're using the value to set a
        # different field we need to also set this one. If our dependence on those references is ever removed we could
        # also remove this.
        T.must(qualifiers[:is]).must(attribute_value)

        # collect the a `is` qualifiers for index type.
        @issue_or_pr_searches << attribute_value if (@issues_index + @prs_index + @pr_fields + @issues_and_pr_fields).include?(attribute_value)

        value_sym = T.cast(attribute_value, String).to_sym
        if @is_qualifier_map.key?(value_sym)
          attribute_name = T.must(@is_qualifier_map[value_sym])[:field]
          attribute_value = T.must(@is_qualifier_map[value_sym])[:value]
        elsif attribute_value == "draft"
          if @current_user&.reviewable_state_searching_enabled?
            attribute_name = :"reviewable-state"
            attribute_value = "draft"
          else
            attribute_name = :draft
            attribute_value = true
          end
        else
          attribute_name = :label
        end
      elsif attribute_name == :linked
        if (@issues_index + @prs_index).include?(attribute_value)
          @linked_searches << attribute_value
        end
      elsif attribute_name == :type
        # collect the `type` qualifiers for index type.
        if (@issues_index + @prs_index).include?(attribute_value)
          @issue_or_pr_searches << attribute_value
        else
          @type_searches << attribute_value
        end
      end

      collection = ::Search::ParsedQuery::BoolCollection.new(attribute_name)
      # Apply the appropriate bool value (should, must, etc), appropriately handling negations and `no:` filters
      if attribute_negative.blank? && attribute_missing.blank?
        if attribute_value.is_a?(Array)
          collection.and_should(attribute_value)
          T.must(qualifiers[attribute_name]).and_should(attribute_value)
        else
          collection.must(attribute_value)
          T.must(qualifiers[attribute_name]).must(attribute_value)
        end
      elsif attribute_negative.present? && attribute_missing.blank?
        collection.must_not(attribute_value)
        T.must(qualifiers[attribute_name]).must_not(attribute_value)
      elsif attribute_missing.present? && @no_value_fields.key?(attribute_name)
        # If the attribute is of the "no:<field>" pattern we need to use the `no_value_fields` hash both to verify
        # that this feature is supported and to get the proper name. Some fields support a pluralized version of the
        # name such as `no:milestone` and `no:milestones`.
        attribute_name = @no_value_fields[attribute_name]

        collection = ::Search::ParsedQuery::BoolCollection.new(attribute_name)
        collection.must(:missing)

        T.must(qualifiers[T.must(attribute_name)]).must(:missing)
      end

      qualifier = Qualifier.new(field: attribute_name, collection: collection)

      if @ownership_fields.include?(attribute_name)
        @ownership_qualifiers << qualifier
        nil
      elsif @aggregation_fields.include?(attribute_name)
        T.must(@aggregation_qualifiers[attribute_name]).must(attribute_value)
        nil
      else
        qualifier
      end
    end

    ## Preprocess and normalizes filter values, transforming @me and only allowing list of values if the
    # filter attribute supports it
    sig { params(filter_term: Hash).returns(T.any(String, T::Array[String])) }
    def preprocess_filter_value(filter_term)
      return "" unless filter_term.has_key?(:value)

      name = filter_term[:attribute].to_sym
      values = filter_term[:value] # value is always an array with the new parser

      supports_comma_separated_values = @enumerable_terms.include?(name)
      unless supports_comma_separated_values && values.length > 1
        # if the filter attribute doesn't support enumarable values, they will be re-joined as if the
        # comma-separated list was a string. This will remove trailing commas, and ideally should error out:
        #   - values with commas should only be treated as single values if they're properly quoted
        # currently:
        #   - ["a", "b", "c"] >-[becomes]-> "a,b,c"
        values = [values.join(",")]
      end

      # Loop to transform @me macro
      values = values.map do |attr_value_component|
        if Search::Query::USERNAME_SEARCH_FIELDS.include?(name) && Search::Query::MACRO_ME.casecmp?(attr_value_component)
          attr_value_component = @current_user&.display_login
          GitHub.dogstats.increment("search.advanced_search.me_macro")
        end
        # unwrap Parslet::Slice
        attr_value_component.to_s
      end

      values.length > 1 ? values : values.first
    end

    sig { returns(T.nilable(IndexType)) }
    def assign_index_type
      issue_or_pr_searches = @issue_or_pr_searches.compact.uniq
      type_searches = @type_searches.compact.uniq
      linked_searches = @linked_searches.compact.uniq

      includes_issues = issue_or_pr_searches.any? { |search| @issues_index.include?(search) }
      includes_prs    = issue_or_pr_searches.any? { |search| (@prs_index + @pr_fields).include?(search) }
      includes_types  = type_searches.any?
      includes_linked_searches = linked_searches.any?

      index_type = nil

      index_type = IndexType::Issue if (includes_issues || includes_types) && (!includes_prs && !includes_linked_searches)
      index_type = IndexType::PullRequest if includes_prs && ((!includes_issues && !includes_types) && !includes_linked_searches)

      if linked_searches.any? && !issue_or_pr_searches.any? { |search| (@issues_index + @prs_index).include?(search) }
        linked_issues = linked_searches.any? { |search| @issues_index.include?(search) }
        linked_prs    = linked_searches.any? { |search| (@prs_index).include?(search) }

        # linked:issue -> returns all **pull-request** that are linked to an issue (have a closing reference)
        index_type = IndexType::PullRequest if linked_issues && !linked_prs

        # linked:pr -> returns all **issues** that are linked to a PR (have a closing reference)
        index_type = IndexType::Issue if linked_prs && !linked_issues
      end

      # check for installation permissions
      if current_installation ||= @current_user.try(:installation)
        permissions = current_installation.permissions
        issue_permission = permissions["issues"]
        pr_permission = permissions["pull_requests"]
        index_type = IndexType::Issue if issue_permission && !pr_permission
        index_type = IndexType::PullRequest if pr_permission && !issue_permission
      end

      index_type
    end

    sig { returns(T::Boolean) }
    def complex?
      @complex
    end

    sig { returns(T::Boolean) }
    def valid_query?
      @is_valid
    end
  end
end
