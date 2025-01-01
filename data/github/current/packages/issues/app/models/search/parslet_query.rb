# typed: true
# frozen_string_literal: true

module Search
  class ParsletQuery
    sig { returns(String) }
    attr_reader :query

    sig { returns(T::Hash[Symbol, ::Search::ParsedQuery::BoolCollection]) }
    attr_reader :qualifiers

    sig { returns(BoolQualifier) }
    attr_reader :conditional_qualifiers

    sig { returns(T::Array[Qualifier]) }
    attr_reader :top_level_qualifiers

    sig { returns(T::Hash[Symbol, ::Search::ParsedQuery::BoolCollection]) }
    attr_reader :aggregation_qualifiers

    sig { returns(T.nilable(IndexType)) }
    attr_reader :index_type

    class InvalidQueryError < ::StandardError; end

    class Qualifier < T::Struct
      const :field, Symbol
      const :collection, ::Search::ParsedQuery::BoolCollection

      sig { params(other: Qualifier).returns(T::Boolean) }
      def ==(other)
        self.field == other.field && self.collection == other.collection
      end
    end

    class QueryQualifier < T::Struct
      const :query, String

      sig { params(other: QueryQualifier).returns(T::Boolean) }
      def ==(other)
        self.query == other.query
      end
    end

    class BoolQualifier < T::Struct
      const :type, Symbol, default: :and
      const :qualifiers, T::Array[T.any(Qualifier, BoolQualifier, QueryQualifier)], default: []

      sig { params(other: BoolQualifier).returns(T::Boolean) }
      def ==(other)
        self.type == other.type && self.qualifiers == other.qualifiers
      end
    end

    class IndexType < T::Enum
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
    # presence_value_fields - The list of fields that support the "no:<field>" or "has:<field>" syntax
    # is_qualifier_map - The map of values supplied in an `is:` filter to their corresponding field names and values
    # enumerable_terms - The list of fields that support comma separated filter values
    # wildcardable_terms - The list of fields that support wildcard (*) as their value
    # top_level_terms - The list of top level fields that shouldn't be included in the list of qualifiers
    # aggregation_fields - The list of fields that may be used to perform aggregations in ElasticSearch
    sig do
      params(
        phrase: String,
        terms: T::Array[Symbol],
        current_user: T.nilable(User),
        presence_value_fields: T::Hash[Symbol, Symbol],
        is_qualifier_map: T::Hash[Symbol, T::Hash[Symbol, T.any(String, Symbol, T::Boolean)]],
        enumerable_terms: T::Array[Symbol],
        wildcardable_terms: T::Array[Symbol],
        top_level_terms: T::Array[Symbol],
        aggregation_fields: T::Array[Symbol],
      ).void
    end
    def initialize(
        phrase,
        terms = [],
        current_user: nil,
        presence_value_fields: {},
        is_qualifier_map: {},
        enumerable_terms: [],
        wildcardable_terms: [],
        top_level_terms: [],
        aggregation_fields: []
    )
      @phrase = phrase.to_s.strip
      @presence_value_fields = presence_value_fields
      @is_qualifier_map = is_qualifier_map
      @current_user = current_user
      @terms = terms.flatten.uniq
      @enumerable_terms = enumerable_terms
      @wildcardable_terms = wildcardable_terms
      @top_level_terms = top_level_terms
      @aggregation_fields = aggregation_fields

      @qualifier_count = 0
      @qualifiers = Hash.new { |h, k| h[k] = ::Search::ParsedQuery::BoolCollection.new(k) }
      @conditional_qualifiers = BoolQualifier.new
      @top_level_qualifiers = []
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

      parser_result_tree = ::Search::Parsers::IssuesParser.new.parse(@phrase)
      parsed_root = parser_result_tree[:root]
      validate_top_level_terms(parsed_root)

      parsed_tree = ::Search::Parsers::IssuesTransformer.new.apply(parser_result_tree)
      parsed = parsed_tree[:root] #the root hash will only have one key:value pair for non-blank queries
      if parsed.is_a?(Hash)
        processed_qualifiers = process_qualifiers(parsed)

        if processed_qualifiers.nil?
          @conditional_qualifiers = BoolQualifier.new
        elsif !processed_qualifiers.is_a?(BoolQualifier)
          @conditional_qualifiers = BoolQualifier.new(qualifiers: [processed_qualifiers])
        else
          @conditional_qualifiers = processed_qualifiers
        end
      else
        @conditional_qualifiers = BoolQualifier.new
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
      @error_message = failure.message
      @is_valid = false
    rescue InvalidQueryError => failure
      STDERR.puts(failure.message) if $console
      GitHub.dogstats.increment("search.advanced_search.invalid_top_level_terms")
      GitHub.logger.info("Invalid usage of top level terms",
        "exception.message" => failure.message,
        "gh.issues_advanced_search.query" => @phrase,
      )
      @error_message = failure.message
      @is_valid = false
    end

    sig { returns(T::Boolean) }
    def complex?
      @complex
    end

    sig { returns(T::Boolean) }
    def valid_query?
      @is_valid
    end

    private

    ## Walk the parsed tree and check if a top level term was explicitly AND'ed together with itself
    sig { params(subtree: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Array[Symbol]) }
    def validate_top_level_terms(subtree)
      return [] unless subtree

      if subtree.has_key?(:and)
        and_subtree = subtree[:and]

        top_level_left_terms = validate_top_level_terms(and_subtree[:left])
        top_level_right_terms = validate_top_level_terms(and_subtree[:right])

        # explicit AND's shouldn't have the same top level term present in their left and right branches
        if and_subtree.has_key?(:explicit_operator)
          invalid_terms = top_level_left_terms & top_level_right_terms

          raise InvalidQueryError.new("Wrong top level terms usage: #{invalid_terms}") unless invalid_terms.empty?
        end

        top_level_left_terms.concat(top_level_right_terms)
      elsif subtree.has_key?(:or)
        # OR nodes won't invalidate a query by themselves, but child subtrees could still be invalid
        or_subtree = subtree[:or]

        validate_top_level_terms(or_subtree[:left])
        validate_top_level_terms(or_subtree[:right])

        []
      elsif subtree.has_key?(:filter_term)
        term = subtree[:filter_term][:attribute].to_sym
        @top_level_terms.include?(term) ? [term] : []
      else
        # non filter terms are ignored
        []
      end
    end

    ## Identify the terms of a search and process then accordingly
    sig { params(parsed: T::Hash[Symbol, T.untyped]).returns(T.any(NilClass, Qualifier, BoolQualifier, QueryQualifier)) }
    def process_qualifiers(parsed)
      if parsed.has_key?(:filter_term)
        if parsed[:filter_term][:missing].present?
          process_no_filter_term(parsed[:filter_term])
        elsif parsed[:filter_term][:attribute] == "has"
          process_has_filter_term(parsed[:filter_term])
        else
          process_filter_term(parsed[:filter_term])
        end
      elsif parsed.has_key?(:text_term)
        process_text_term(parsed[:text_term].to_s)
      elsif parsed.has_key?(:mention_term)
        process_mention_term(parsed[:mention_term])
      elsif parsed.has_key?(:or)
        @complex = true
        process_subtree(:or, parsed)
      elsif parsed.has_key?(:and)
        process_subtree(:and, parsed)
      end
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

    ## Process simple text terms
    sig { params(query: String,).returns(QueryQualifier) }
    def process_text_term(query)
      @query_parts << query
      QueryQualifier.new(query:)
    end

    ## Process mention terms and turn them into filters:
    # (legacy compatibility)
    # - repo_mention: @{user_name}/{repo_name}
    #                 -@{user_name}/{repo_name}
    # - user_mention: @{user_name}
    #                 -@{user_name}
    sig { params(mention_term: Hash).returns(T.nilable(Qualifier)) }
    def process_mention_term(mention_term)
      value = mention_term[:user_value]

      is_repo_mention = mention_term.has_key?(:repository_value)
      value = "#{value}/#{mention_term[:repository_value]}" if is_repo_mention

      process_filter_term({
        attribute: is_repo_mention ? :repo : :user,
        value: [value],
        negative: mention_term[:negative]
      })
    end

    ## Process filter terms matched against:
    #  has:{attribute}
    sig { params(filter_term: Hash).returns(T.nilable(T.any(Qualifier, QueryQualifier))) }
    def process_has_filter_term(filter_term)

      value_sym = filter_term[:value].first.to_sym
      return nil unless @presence_value_fields.has_key?(value_sym) || filter_term[:negative].present?

      attribute_name = @presence_value_fields[value_sym]
      attribute_value = ::Search::Filter::EXISTS

      process_filter_term({
        attribute: attribute_name,
        value: [attribute_value],
        negative: filter_term[:negative]
      })
    end

    ## Process filter terms matched against:
    ##  no:{attribute}
    sig { params(filter_term: Hash).returns(T.nilable(Qualifier)) }
    def process_no_filter_term(filter_term)
      attribute_name = filter_term[:attribute].to_sym
      return unless @presence_value_fields.include?(attribute_name)

      GitHub.dogstats.increment("search.advanced_search.qualifier", tags: ["field:#{attribute_name}"])
      @qualifier_count += 1

      # If the attribute is of the "no:<field>" pattern we need to use the `presence_value_fields` hash both to verify
      # that this feature is supported and to get the proper name. Some fields support a pluralized version of the
      # name such as `no:milestone` and `no:milestones`.
      attribute_name = T.must(@presence_value_fields[attribute_name])
      attribute_value = preprocess_filter_value(filter_term)

      collection = ::Search::ParsedQuery::BoolCollection.new(attribute_name)
      collection.must(:missing)

      T.must(qualifiers[attribute_name]).must(:missing)

      Qualifier.new(field: attribute_name, collection: collection)
    end

    ## Process filter terms matched against:
    ##  {attribute:value}
    ##  -{attribute:value}
    sig { params(filter_term: Hash).returns(T.nilable(Qualifier)) }
    def process_filter_term(filter_term)
      attribute_name = filter_term[:attribute].to_sym
      attribute_negative = filter_term[:negative]

      return unless @terms.include?(attribute_name)
      GitHub.dogstats.increment("search.advanced_search.qualifier", tags: ["field:#{attribute_name}"])
      @qualifier_count += 1

      attribute_value = preprocess_filter_value(filter_term)

      if attribute_name == :state && %w(merged draft).include?(attribute_value)
        attribute_name = :is
      end

      if attribute_name == :is
        if (@issues_index + @prs_index).include?(attribute_value)
          if attribute_negative.present?
            attribute_value = invert_issue_pr_value(T.cast(attribute_value, String))
            attribute_negative = nil
          end
        end

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
        # collect the a `type` qualifiers for index type.
        if (@issues_index + @prs_index).include?(attribute_value)
          if attribute_negative.present?
            attribute_value = invert_issue_pr_value(T.cast(attribute_value, String))
            attribute_negative = nil
          end
          @issue_or_pr_searches << attribute_value
        else
          @type_searches << attribute_value
        end
      end
      @issue_or_pr_searches.uniq!

      collection = ::Search::ParsedQuery::BoolCollection.new(attribute_name)
      # Apply the appropriate bool value (should, must, etc), appropriately handling negations and `no:` filters
      if attribute_negative.blank?
        if attribute_value.is_a?(Array)
          collection.and_should(attribute_value)
          T.must(qualifiers[attribute_name]).and_should(attribute_value)
        else
          collection.must(attribute_value)
          T.must(qualifiers[attribute_name]).must(attribute_value)
        end
      else
        collection.must_not(attribute_value)
        T.must(qualifiers[attribute_name]).must_not(attribute_value)
      end

      qualifier = Qualifier.new(field: attribute_name, collection: collection)

      if @top_level_terms.include?(attribute_name)
        @top_level_qualifiers << qualifier
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
    sig { params(filter_term: Hash).returns(T.any(Symbol, String, T::Array[String])) }
    def preprocess_filter_value(filter_term)
      return "" unless filter_term.has_key?(:value)

      name = filter_term[:attribute].to_sym
      values = filter_term[:value] # value is always an array with the new parser

      supports_comma_separated_values = @enumerable_terms.include?(name)
      if !supports_comma_separated_values && values.length > 1
        # Rejoin comma-separated values when enumerated values are not supported by the filter
        # This will remove any trailing commas of values:
        #   e.g.:
        #   {some_single_value_filter}:a,b,c,
        #
        #   a,b,c, >-[is parsed into]-> ["a", "b", "c"] >-[becomes]-> a,b,c
        values = [values.join(",")]
      end

      # Loop to transform @me macro
      values = values.map do |attr_value_component|
        next ::Search::Filter::EXISTS if attr_value_component == ::Search::Filter::EXISTS

        next ::Search::Filter::EXISTS if (attr_value_component == ::Search::Filter::WILDCARD) && @wildcardable_terms.include?(name)

        if Search::Query::USERNAME_SEARCH_FIELDS.include?(name) && Search::Query::MACRO_ME.casecmp?(attr_value_component)
          attr_value_component = @current_user&.display_login
          GitHub.dogstats.increment("search.advanced_search.me_macro")
        elsif Search::Query::COPILOT_SEARCH_FIELDS.include?(name) && Search::Query::MACRO_COPILOT.casecmp?(attr_value_component)
          if Apps::Privileged::CopilotPullRequestReviewer.installed?
            attr_value_component = "#{Apps::Privileged::CopilotPullRequestReviewer::SLUG}#{Bot::LOGIN_SUFFIX}"
            GitHub.dogstats.increment("search.advanced_search.copilot_macro")
          end
        end
        # unwrap Parslet::Slice
        attr_value_component.to_s
      end

      values.length > 1 ? values : values.first
    end

    # Negative :type or :is filters with "issue" or "pr" values have to be converted to the opposite index
    # instead of generating an actual negative query of the index
    sig { params(value: String).returns(String) }
    def invert_issue_pr_value(value)
      if @issues_index.include?(value)
        "pr"
      elsif @prs_index.include?(value)
        "issue"
      else
        value
      end
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

      linked_issues = linked_searches.any? { |search| @issues_index.include?(search) }
      linked_prs    = linked_searches.any? { |search| @prs_index.include?(search) }

      index_type = nil

      index_type = IndexType::Issue if (includes_issues || includes_types) && (!includes_prs && (!includes_linked_searches || linked_prs))
      index_type = IndexType::PullRequest if includes_prs && ((!includes_issues && !includes_types) && (!includes_linked_searches || linked_issues))

      if includes_linked_searches && !issue_or_pr_searches.any? { |search| (@issues_index + @prs_index).include?(search) }
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
  end
end
