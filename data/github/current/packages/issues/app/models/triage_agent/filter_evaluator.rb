# typed: strict
# frozen_string_literal: true

module TriageAgent
  # Evaluates a GitHub advanced search query against a single Issue object
  # in-memory to determine if it matches. Used by the triage agent to decide
  # whether an issue should be triaged based on a per-trigger inclusion filter.
  #
  # Supported qualifiers (subset relevant to newly-created issues):
  #   - label:<name>         — issue has label with given name (comma-separated supported)
  #   - assignee:<login>     — issue is assigned to given user
  #   - author:<login>       — issue was created by given user
  #   - milestone:<title>    — issue has given milestone
  #   - type:<name>          — issue has given issue type
  #   - state:open           — issue is open
  #   - state:closed         — issue is closed
  #   - has:label            — issue has any label
  #   - has:assignee         — issue has any assignee
  #   - has:milestone        — issue has a milestone
  #   - has:type             — issue has an issue type
  #   - no:label             — issue has no labels
  #   - no:assignee          — issue has no assignees
  #   - no:milestone         — issue has no milestone
  #   - no:type              — issue has no issue type
  #   - is:open              — issue is open
  #   - is:closed            — issue is closed
  #
  # No-op qualifiers (silently ignored):
  #   - is:issue / type:issue — always true for issues, treated as no-op to
  #                             prevent accidentally skipping all issues
  #
  # Rejected qualifiers:
  #   - is:pr / type:pr — only issues are supported
  #
  # Boolean operators: AND (implicit/explicit), OR
  # Negation: -qualifier:value (e.g., -label:bug)
  # Parentheses for grouping
  # Note: The NOT keyword is not supported. Use - prefix instead.
  #
  # Fail-open semantics: when the query is blank, invalid, free-text only,
  # or triggers an exception, the evaluator returns a match so that the
  # issue is triaged rather than silently skipped.
  class FilterEvaluator
    # Supported qualifier terms for filter evaluation
    SUPPORTED_TERMS = T.let([:label, :assignee, :author, :milestone, :type, :issue_type, :is, :has, :no, :state].freeze, T::Array[Symbol])

    # Fields that support "no:<field>" and "has:<field>" syntax
    PRESENCE_VALUE_FIELDS = T.let({
      label: :label,
      labels: :label,
      assignee: :assignee,
      milestone: :milestone,
      milestones: :milestone,
      type: :issue_type,
    }.freeze, T::Hash[Symbol, Symbol])

    # Mapping of "is:<value>" to field/value pairs (subset relevant to issues)
    IS_QUALIFIER_MAP = T.let({
      issue: { field: :type, value: "issue" },
      open: { field: :state, value: "open" },
      closed: { field: :state, value: "closed" },
    }.freeze, T::Hash[Symbol, T::Hash[Symbol, T.any(String, Symbol)]])

    # Result of evaluating a filter query against an issue.
    class Result < T::Struct
      const :matched, T::Boolean
      const :error, T.nilable(String)
    end

    # Evaluates the filter query against the given issue.
    # Returns a Result indicating whether the issue matched the filter.
    #
    # Uses fail-open semantics: when the query is blank, invalid, or
    # cannot be parsed, returns a match result so that the issue is
    # triaged rather than silently skipped. Errors are reported via
    # the error field for logging but do not prevent triage.
    #
    # @param issue [Issue] — typed as untyped to avoid Packwerk dependency from lib/ to packages/issues
    sig { params(query: String, issue: T.untyped).returns(Result) }
    def self.evaluate(query, issue)
      return Result.new(matched: true, error: nil) if query.blank?

      parsed = ::Search::ParsletQuery.new(
        query,
        SUPPORTED_TERMS,
        presence_value_fields: PRESENCE_VALUE_FIELDS,
        is_qualifier_map: IS_QUALIFIER_MAP,
        enumerable_terms: [:label]
      )

      unless parsed.valid_query?
        return Result.new(matched: true, error: parsed.invalid_reason)
      end

      # Reject queries targeting pull requests — we only evaluate issues
      if parsed.index_type == ::Search::ParsletQuery::IndexType::PullRequest
        return Result.new(matched: false, error: "filter contains pull request qualifiers (is:pr or type:pr) which are not supported")
      end

      # If the query is only free-text with no qualifiers, treat as matching (fail-open)
      if parsed.conditional_qualifiers.qualifiers.empty?
        return Result.new(matched: true, error: nil)
      end

      # Strip no-op qualifiers (is:issue / type:issue) and check for
      # always-false qualifiers (is:closed / state:closed on new issues)
      sanitized = sanitize_qualifiers(parsed.conditional_qualifiers)
      return sanitized if sanitized.is_a?(Result)

      # After sanitization, if no qualifiers remain, treat as matching (fail-open)
      if sanitized.qualifiers.empty?
        return Result.new(matched: true, error: nil)
      end

      matched = evaluate_bool_qualifier(sanitized, issue)
      Result.new(matched: matched, error: nil)
    rescue StandardError => e
      Result.new(matched: true, error: "filter evaluation error: #{e.message}")
    end

    # Evaluates a BoolQualifier tree against the issue.
    # Empty groups return false so that stripped no-op subtrees don't
    # become unconditional matches (e.g. inside an OR branch).
    sig { params(bool_qual: ::Search::ParsletQuery::BoolQualifier, issue: T.untyped).returns(T::Boolean) }
    def self.evaluate_bool_qualifier(bool_qual, issue)
      return false if bool_qual.qualifiers.empty?

      results = bool_qual.qualifiers.map do |qual|
        case qual
        when ::Search::ParsletQuery::Qualifier
          evaluate_qualifier_with_collection(qual.field, qual.collection, issue)
        when ::Search::ParsletQuery::BoolQualifier
          evaluate_bool_qualifier(qual, issue)
        when ::Search::ParsletQuery::QueryQualifier
          # Free-text search terms are not meaningful for filter evaluation;
          # treat as matching (fail-open) so they don't prevent triage.
          true
        end
      end

      bool_qual.type == :or ? results.any? : results.all?
    end

    # Evaluates a qualifier with its BoolCollection against an issue.
    # BoolCollection has must (positive), must_not (negated), and should (OR) values.
    sig { params(field: Symbol, collection: ::Search::ParsedQuery::BoolCollection, issue: T.untyped).returns(T::Boolean) }
    def self.evaluate_qualifier_with_collection(field, collection, issue)
      # Handle "must" values - all must match
      must_ok = !collection.must? || collection.must.all? { |value| matches_field?(field, value, issue) }

      # Handle "must_not" values - none must match
      must_not_ok = !collection.must_not? || collection.must_not.none? { |value| matches_field?(field, value, issue) }

      # Handle "should" values - at least one must match (if present)
      should_ok = !collection.should? || collection.should.any? { |value| matches_field?(field, value, issue) }

      # Handle "and_should" values - comma-separated values like label:bug,enhancement
      # Each value in the flattened array must match individually (AND semantics)
      and_should_ok = !collection.and_should? || collection.and_should.flatten.all? { |value| matches_field?(field, value, issue) }

      must_ok && must_not_ok && should_ok && and_should_ok
    end

    # Matches a single field/value pair against the issue.
    sig { params(field: Symbol, value: T.untyped, issue: T.untyped).returns(T::Boolean) }
    def self.matches_field?(field, value, issue)
      value_str = value.to_s

      # Handle special :missing value for "no:" qualifiers
      if value_str == "missing" || value == ::Search::Filter::MISSING
        return evaluate_missing(field, issue)
      end

      # Handle special :exists value for "has:" qualifiers
      if value_str == "exists" || value == ::Search::Filter::EXISTS
        return evaluate_exists(field, issue)
      end

      case field
      when :label
        issue.labels.any? { |label| label.name.casecmp?(value_str) }
      when :assignee
        login = value_str.delete_prefix("@")
        issue.assignees.any? { |assignee| assignee.display_login.casecmp?(login) }
      when :author
        login = value_str.delete_prefix("@")
        issue.user&.display_login&.casecmp?(login) || false
      when :milestone
        issue.milestone&.title&.casecmp?(value_str) || false
      when :type, :issue_type
        if value_str.casecmp?("issue")
          # is:issue / type:issue — treated as no-op (always true, ignore to prevent
          # accidentally skipping all issues). Callers should strip this qualifier.
          true
        else
          issue.respond_to?(:issue_type) && (issue.issue_type&.name&.casecmp?(value_str) || false)
        end
      when :state
        case value_str.downcase
        when "open" then issue.open?
        when "closed" then issue.closed?
        else false
        end
      else
        # Unknown field — treat as non-matching so the qualifier cannot
        # contribute to a positive match.
        false
      end
    end

    # Evaluates "no:" qualifier (field is missing/empty).
    sig { params(field: Symbol, issue: T.untyped).returns(T::Boolean) }
    def self.evaluate_missing(field, issue)
      case field
      when :label
        issue.labels.empty?
      when :assignee
        issue.assignees.empty?
      when :milestone
        issue.milestone.nil?
      when :issue_type
        !issue.respond_to?(:issue_type) || issue.issue_type.nil?
      else
        false
      end
    end

    # Evaluates "has:" qualifier (field exists/is present).
    sig { params(field: Symbol, issue: T.untyped).returns(T::Boolean) }
    def self.evaluate_exists(field, issue)
      case field
      when :label
        issue.labels.any?
      when :assignee
        issue.assignees.any?
      when :milestone
        issue.milestone.present?
      when :issue_type
        issue.respond_to?(:issue_type) && issue.issue_type.present?
      else
        false
      end
    end

    # Recursively processes a BoolQualifier tree:
    # - Removes no-op qualifiers (is:issue / type:issue)
    # - Returns an error Result if always-false qualifiers are found
    #   (is:closed / state:closed — new issues are always open)
    sig { params(bool_qual: ::Search::ParsletQuery::BoolQualifier).returns(T.any(::Search::ParsletQuery::BoolQualifier, Result)) }
    def self.sanitize_qualifiers(bool_qual)
      filtered = bool_qual.qualifiers.filter_map do |qual|
        case qual
        when ::Search::ParsletQuery::Qualifier
          # Detect always-false qualifiers: is:closed / state:closed
          if always_false_qualifier?(qual)
            return Result.new(
              matched: false,
              error: "filter contains 'is:closed' or 'state:closed' which can never match newly-created issues"
            )
          end

          # Strip no-op qualifiers: is:issue / type:issue
          next nil if noop_qualifier?(qual)

          qual
        when ::Search::ParsletQuery::BoolQualifier
          result = sanitize_qualifiers(qual)
          return result if result.is_a?(Result)
          # Drop empty subtrees so stripped no-ops can't turn an OR branch
          # into an unconditional match.
          next nil if result.qualifiers.empty?
          result
        else
          qual
        end
      end

      ::Search::ParsletQuery::BoolQualifier.new(type: bool_qual.type, qualifiers: filtered)
    end

    # Returns true if the qualifier is a no-op that should be silently removed.
    # is:issue and type:issue always match (evaluator only runs on issues),
    # so including them in a filter would skip all issues — almost certainly a mistake.
    sig { params(qual: ::Search::ParsletQuery::Qualifier).returns(T::Boolean) }
    def self.noop_qualifier?(qual)
      return false unless qual.field == :type || qual.field == :is
      return false unless qual.collection.must?

      qual.collection.must.any? { |v| v.to_s.casecmp?("issue") }
    end

    # Returns true if the qualifier can never match a newly-created issue.
    # is:closed and state:closed are always false for new issues.
    sig { params(qual: ::Search::ParsletQuery::Qualifier).returns(T::Boolean) }
    def self.always_false_qualifier?(qual)
      return false unless qual.field == :state
      return false unless qual.collection.must?

      qual.collection.must.any? { |v| v.to_s.casecmp?("closed") }
    end

    private_class_method :evaluate_bool_qualifier, :evaluate_qualifier_with_collection,
      :matches_field?, :evaluate_missing, :evaluate_exists, :sanitize_qualifiers,
      :noop_qualifier?, :always_false_qualifier?
  end
end
