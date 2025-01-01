# typed: false
# frozen_string_literal: true

require "test_helper"

class SearchParsletQueryTest < GitHub::TestCase
  include GitHub::LoggerHelper

  test "blank" do
    parser = ::Search::ParsletQuery.new("")

    assert_empty parser.query
    assert_empty parser.qualifiers
    assert_equal build_bool_qualifier(:and, []), parser.conditional_qualifiers
  end

  test "bad query logging" do
    query = "("
    expected_log = {
      Body: "Parslet failed to parse query",
      "exception.message": "Expected one of [or:(left:AND_EXPRESSION WHITE_SPACE OR_OPERATOR WHITE_SPACE right:OR_EXPRESSION), AND_EXPRESSION] at line 1 char 1.",
      "gh.issues_advanced_search.query": query
    }

    assert_logged(**expected_log) do
      parser = ::Search::ParsletQuery.new(query)
    end
  end

  test "term" do
    parser = ::Search::ParsletQuery.new("emojis", ::Search::Queries::IssueQuery::field_list)

    assert_equal "emojis", parser.query
    assert_empty parser.qualifiers
    assert_equal build_bool_qualifier(:and, [build_query_qualifier("emojis")]), parser.conditional_qualifiers
  end

  test "multiple terms" do
    parser = ::Search::ParsletQuery.new("multiple terms", ::Search::Queries::IssueQuery::field_list)

    assert_equal "multiple terms", parser.query
    assert_empty parser.qualifiers
    assert_equal build_bool_qualifier(:and, [
      build_query_qualifier("multiple"),
      build_query_qualifier("terms"),
    ]), parser.conditional_qualifiers
  end

  test "single qualifier" do
    parser = ::Search::ParsletQuery.new("is:issue", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

    assert_empty parser.query
    assert_equal ["issue"], parser.qualifiers[:type].must
    assert_equal build_single_term_qualifier(:type, "issue"), parser.conditional_qualifiers
  end

  test "removes quotes from values" do
    parser = ::Search::ParsletQuery.new("milestone:\"test title\"", ::Search::Queries::IssueQuery::field_list)

    assert_empty parser.query
    assert_equal ["test title"], parser.qualifiers[:milestone].must
    assert_equal build_single_term_qualifier(:milestone, "test title"), parser.conditional_qualifiers
  end

  test "removes quotes from values with multiple terms" do
    parser = ::Search::ParsletQuery.new("milestone:\"test title\" label:wontfix", ::Search::Queries::IssueQuery::field_list)
    expected = build_bool_qualifier(:and, [
      build_qualifier(:milestone, "test title"),
      build_qualifier(:label, "wontfix"),
    ])

    assert_empty parser.query
    assert_equal ["test title"], parser.qualifiers[:milestone].must
    assert_equal ["wontfix"], parser.qualifiers[:label].must
    assert_equal expected, parser.conditional_qualifiers
  end

  test "query with leading and trailing whitespace is stripped" do
    parser = ::Search::ParsletQuery.new("  bug  state:open  ", ::Search::Queries::IssueQuery::field_list)

    expected = build_bool_qualifier(:and, [
      build_query_qualifier("bug"),
      build_qualifier(:state, "open")
    ])

    assert_equal "bug", parser.query
    assert_equal expected, parser.conditional_qualifiers
    assert_equal ["open"], parser.qualifiers[:state].must
  end

  test "accepts values with plus symbol (+)" do
    parser = ::Search::ParsletQuery.new("label:c++", ::Search::Queries::IssueQuery::field_list)

    assert_empty parser.query
    assert_equal ["c++"], parser.qualifiers[:label].must
    assert_equal build_single_term_qualifier(:label, "c++"), parser.conditional_qualifiers
  end

  test "accepts values with exclamation symbol (!)" do
    parser = ::Search::ParsletQuery.new("is:issue AND state:open AND label:1-liner-!!!!", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)
    expected = build_bool_qualifier(:and, [
      build_qualifier(:type, "issue"),
      build_qualifier(:state, "open"),
      build_qualifier(:label, "1-liner-!!!!")
    ])

    assert_empty parser.query
    assert_equal ["issue"], parser.qualifiers[:type].must
    assert_equal ["open"], parser.qualifiers[:state].must
    assert_equal ["1-liner-!!!!"], parser.qualifiers[:label].must
    assert_equal expected, parser.conditional_qualifiers
  end

  context "single qualifier" do
    test "with single term" do
      parser = ::Search::ParsletQuery.new("is:issue emojis", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)
      expected = build_bool_qualifier(:and, [
        build_qualifier(:type, "issue"),
        build_query_qualifier("emojis"),
      ])

      assert_equal "emojis", parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
    end

    test "with multiple terms" do
      parser = ::Search::ParsletQuery.new("bugs is:issue emojis", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)
      expected = build_bool_qualifier(:and, [
        build_query_qualifier("bugs"),
        build_qualifier(:type, "issue"),
        build_query_qualifier("emojis"),
      ])

      refute parser.complex?
      assert_equal "bugs emojis", parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
    end
  end

  # Queries without explicit ANDs are implicitly ANDed together
  context "multiple qualifiers" do
    test "are implicitly ANDed together" do
      expected = build_bool_qualifier(:and, [
        build_qualifier(:type, "issue"),
        build_qualifier(:state, "open"),
        build_qualifier(:label, "bug"),
      ])

      parser = ::Search::ParsletQuery.new("is:issue state:open label:bug", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      refute parser.complex?
      assert_empty parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal ["open"], parser.qualifiers[:state].must
      assert_equal ["bug"], parser.qualifiers[:label].must
    end

    test "with single term" do
      expected = build_bool_qualifier(:and, [
        build_qualifier(:type, "issue"),
        build_qualifier(:state, "open"),
        build_qualifier(:label, "bug"),
        build_query_qualifier("emojis"),
      ])

      parser = ::Search::ParsletQuery.new("is:issue state:open label:bug emojis", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      assert_equal "emojis", parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal ["open"], parser.qualifiers[:state].must
      assert_equal ["bug"], parser.qualifiers[:label].must
    end

    test "with explicit ANDs" do
      expected = build_bool_qualifier(:and, [
        build_qualifier(:type, "issue"),
        build_qualifier(:state, "open"),
        build_qualifier(:label, "bug"),
      ])

      parser = ::Search::ParsletQuery.new("is:issue AND state:open AND label:bug", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      refute parser.complex?
      assert_empty parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal ["open"], parser.qualifiers[:state].must
      assert_equal ["bug"], parser.qualifiers[:label].must
    end

    test "with nested implicit ANDs" do
      expected = build_bool_qualifier(:or, [
        build_qualifier(:type, "issue"),
        build_bool_qualifier(:and, [
          build_qualifier(:state, "open"),
          build_qualifier(:label, "bug"),
        ]),
      ])

      parser = ::Search::ParsletQuery.new("is:issue OR (state:open label:bug)", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      assert parser.complex?
      assert_empty parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal ["open"], parser.qualifiers[:state].must
      assert_equal ["bug"], parser.qualifiers[:label].must
    end

    test "with parentheses should be grouped into a single array" do
      expected = build_bool_qualifier(:and, [
        build_qualifier(:type, "issue"),
        build_qualifier(:state, "open"),
        build_qualifier(:label, "bug"),
      ])

      parser = ::Search::ParsletQuery.new("is:issue AND (state:open AND label:bug)", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      refute parser.complex?
      assert_empty parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal ["open"], parser.qualifiers[:state].must
      assert_equal ["bug"], parser.qualifiers[:label].must
    end

    test "with OR" do
      expected = build_bool_qualifier(:or, [
        build_qualifier(:type, "issue"),
        build_qualifier(:state, "open"),
        build_qualifier(:label, "bug"),
      ])

      parser = ::Search::ParsletQuery.new("is:issue OR state:open OR label:bug", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      assert parser.complex?
      assert_empty parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal ["open"], parser.qualifiers[:state].must
      assert_equal ["bug"], parser.qualifiers[:label].must
    end

    test "with OR with parentheses" do
      expected = build_bool_qualifier(:or, [
        build_qualifier(:type, "issue"),
        build_qualifier(:state, "open"),
        build_qualifier(:label, "bug"),
      ])

      parser = ::Search::ParsletQuery.new("is:issue OR (state:open OR label:bug)", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      assert parser.complex?
      assert_empty parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal ["open"], parser.qualifiers[:state].must
      assert_equal ["bug"], parser.qualifiers[:label].must
    end

    test "with OR and AND" do
      expected = build_bool_qualifier(:and, [
        build_qualifier(:type, "issue"),
        build_bool_qualifier(:or, [
          build_qualifier(:state, "open"),
          build_qualifier(:label, "bug"),
        ]),
      ])

      parser = ::Search::ParsletQuery.new("is:issue AND (state:open OR label:bug)", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      assert parser.complex?
      assert_empty parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal ["open"], parser.qualifiers[:state].must
      assert_equal ["bug"], parser.qualifiers[:label].must
    end

    test "with AND and OR" do
      expected = build_bool_qualifier(:or, [
        build_qualifier(:type, "issue"),
        build_bool_qualifier(:and, [
          build_qualifier(:state, "open"),
          build_qualifier(:label, "bug"),
        ])
      ])

      parser = ::Search::ParsletQuery.new("is:issue OR (state:open AND label:bug)", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      assert parser.complex?
      assert_empty parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal ["open"], parser.qualifiers[:state].must
      assert_equal ["bug"], parser.qualifiers[:label].must
    end

    test "cause implicit grouping around the AND" do
      expected = build_bool_qualifier(:or, [
        build_qualifier(:type, "issue"),
        build_bool_qualifier(:and, [
          build_qualifier(:state, "open"),
          build_qualifier(:label, "bug"),
        ]),
      ])

      parser = ::Search::ParsletQuery.new("is:issue OR state:open AND label:bug", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      assert parser.complex?
      assert_empty parser.query
      assert_equal expected, parser.conditional_qualifiers
      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal ["open"], parser.qualifiers[:state].must
      assert_equal ["bug"], parser.qualifiers[:label].must
    end
  end

  context "@me macro substitution" do
    test "for valid username search fields" do
      user = create :user
      parser = ::Search::ParsletQuery.new("author:@me", ::Search::Queries::IssueQuery::field_list, current_user: user)

      assert_equal [user.display_login], parser.qualifiers[:author].must
      assert_equal build_single_term_qualifier(:author, user.display_login), parser.conditional_qualifiers
    end

    test "doesn't happen for non username search fields" do
      user = create :user
      parser = ::Search::ParsletQuery.new("label:@me", ::Search::Queries::IssueQuery::field_list, current_user: user)

      assert_equal ["@me"], parser.qualifiers[:label].must
      assert_equal build_single_term_qualifier(:label, "@me"), parser.conditional_qualifiers
    end
  end

  context "@copilot macro substitution" do
    test "for valid copilot search fields" do
      user = create :user
      parser = ::Search::ParsletQuery.new("reviewed-by:@copilot", ::Search::Queries::IssueQuery::field_list, current_user: user)

      assert_equal ["@copilot"], parser.qualifiers[:"reviewed-by"].must
      assert_equal build_single_term_qualifier(:"reviewed-by", "@copilot"), parser.conditional_qualifiers
    end

    test "doesn't happen for non copilot search fields" do
      user = create :user
      parser = ::Search::ParsletQuery.new("label:@copilot", ::Search::Queries::IssueQuery::field_list, current_user: user)

      assert_equal ["@copilot"], parser.qualifiers[:label].must
      assert_equal build_single_term_qualifier(:label, "@copilot"), parser.conditional_qualifiers
    end
  end


  context "terms with wildcard support" do
    test "assignee:*" do
      parser = ::Search::ParsletQuery.new(
        "assignee:*",
        ::Search::Queries::IssueQuery::field_list,
        is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP,
        wildcardable_terms: ::Search::Queries::ConditionalIssueQuery::WILDCARDABLE_TERMS,
      )

      assert_equal [:exists], parser.qualifiers[:assignee].must
    end

    test "milestone:*" do
      parser = ::Search::ParsletQuery.new(
        "milestone:*",
        ::Search::Queries::IssueQuery::field_list,
        is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP,
        wildcardable_terms: ::Search::Queries::ConditionalIssueQuery::WILDCARDABLE_TERMS,
      )

      assert_equal [:exists], parser.qualifiers[:milestone].must
    end

    test "wildcard terms in a complex query" do
      parser = ::Search::ParsletQuery.new(
        "(label:p1 milestone:*) OR (label:p0 assignee:*)",
        ::Search::Queries::IssueQuery::field_list,
        is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP,
        wildcardable_terms: ::Search::Queries::ConditionalIssueQuery::WILDCARDABLE_TERMS,
      )

      expected = build_bool_qualifier(:or, [
        build_bool_qualifier(:and, [
          build_qualifier(:label, "p1"),
          build_qualifier(:milestone, :exists),
        ]),
        build_bool_qualifier(:and, [
          build_qualifier(:label, "p0"),
          build_qualifier(:assignee, :exists),
        ]),
      ])

      assert parser.complex?
      assert_equal expected, parser.conditional_qualifiers
    end
  end

  test "negative qualifiers" do
    expected = build_bool_qualifier(:and, [
      build_qualifier(:type, "issue"),
      build_qualifier(:label, "bug", true)
    ])

    parser = ::Search::ParsletQuery.new("is:issue -label:bug", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

    assert_empty parser.query
    assert_equal expected, parser.conditional_qualifiers
    assert_equal ["issue"], parser.qualifiers[:type].must
    assert_equal ["bug"], parser.qualifiers[:label].must_not
  end

  test "implicit AND between terms" do
    expected = build_bool_qualifier(:or, [
      build_qualifier(:label, "bug"),
      build_bool_qualifier(:and, [
        build_qualifier(:author, "monalisa"),
        build_qualifier(:sort, "created-desc"),
      ]),
    ])

    parser = ::Search::ParsletQuery.new("label:bug OR author:monalisa sort:created-desc", ::Search::Queries::IssueQuery::field_list)
    assert parser.complex?
    assert_empty parser.query
    assert_equal expected, parser.conditional_qualifiers
  end

  test "invalid filter term" do
    expected = build_bool_qualifier(:and, [
      build_qualifier(:author, "monalisa")
    ])

    parser = ::Search::ParsletQuery.new("color:red OR author:monalisa", ::Search::Queries::IssueQuery::field_list)
    assert_empty parser.query
    assert_equal expected, parser.conditional_qualifiers
  end

  context "index" do
    context "App installations" do
      test "permissions for issues only" do
        installation = make_integration_installation(repository: create(:private_repository), permissions: { "issues" => :read })

        is_issue_allowed  = ::Search::ParsletQuery.new("is:issue", ::Search::Queries::IssueQuery::field_list, current_user: installation.bot)
        is_pr_not_allowed = ::Search::ParsletQuery.new("is:pr", ::Search::Queries::IssueQuery::field_list, current_user: installation.bot)

        assert_equal Search::ParsletQuery::IndexType::Issue, is_issue_allowed.index_type
        assert_equal Search::ParsletQuery::IndexType::Issue, is_pr_not_allowed.index_type
      end

      test "permissions for pull-requests only" do
        installation = make_integration_installation(repository: create(:private_repository), permissions: { "pull_requests" => :read })

        is_issue_not_allowed = ::Search::ParsletQuery.new("is:issue", ::Search::Queries::IssueQuery::field_list, current_user: installation.bot)
        is_pr_allowed        = ::Search::ParsletQuery.new("is:pr", ::Search::Queries::IssueQuery::field_list, current_user: installation.bot)

        assert_equal Search::ParsletQuery::IndexType::PullRequest, is_issue_not_allowed.index_type
        assert_equal Search::ParsletQuery::IndexType::PullRequest, is_pr_allowed.index_type
      end

      test "permissions for issues and pull-requests" do
        installation = make_integration_installation(repository: create(:private_repository), permissions: { "issues" => :read, "pull_requests" => :read })

        is_issue_allowed = ::Search::ParsletQuery.new("is:issue", ::Search::Queries::IssueQuery::field_list, current_user: installation.bot)
        is_pr_allowed    = ::Search::ParsletQuery.new("is:pr", ::Search::Queries::IssueQuery::field_list, current_user: installation.bot)

        assert_equal Search::ParsletQuery::IndexType::Issue, is_issue_allowed.index_type
        assert_equal Search::ParsletQuery::IndexType::PullRequest, is_pr_allowed.index_type
      end
    end

    test "issues index type" do
      is_issue    = ::Search::ParsletQuery.new("is:issue", ::Search::Queries::IssueQuery::field_list)
      is_issues   = ::Search::ParsletQuery.new("is:issues", ::Search::Queries::IssueQuery::field_list)
      type_issue  = ::Search::ParsletQuery.new("type:issue", ::Search::Queries::IssueQuery::field_list)
      type_issues = ::Search::ParsletQuery.new("type:issues", ::Search::Queries::IssueQuery::field_list)
      type_task   = ::Search::ParsletQuery.new("type:Task", ::Search::Queries::IssueQuery::field_list)
      type_epic   = ::Search::ParsletQuery.new("type:Epic", ::Search::Queries::IssueQuery::field_list)
      type_cat    = ::Search::ParsletQuery.new("type:cat", ::Search::Queries::IssueQuery::field_list)

      assert_equal Search::ParsletQuery::IndexType::Issue, is_issue.index_type
      assert_equal Search::ParsletQuery::IndexType::Issue, is_issues.index_type
      assert_equal Search::ParsletQuery::IndexType::Issue, type_issue.index_type
      assert_equal Search::ParsletQuery::IndexType::Issue, type_issues.index_type
      assert_equal Search::ParsletQuery::IndexType::Issue, type_task.index_type
      assert_equal Search::ParsletQuery::IndexType::Issue, type_epic.index_type
      assert_equal Search::ParsletQuery::IndexType::Issue, type_cat.index_type
    end

    test "pull-requests index type" do
      is_pr             = ::Search::ParsletQuery.new("is:pr", ::Search::Queries::IssueQuery::field_list)
      is_pull_request   = ::Search::ParsletQuery.new("is:pull-request", ::Search::Queries::IssueQuery::field_list)
      is_merged         = ::Search::ParsletQuery.new("is:merged", ::Search::Queries::IssueQuery::field_list)
      is_queued         = ::Search::ParsletQuery.new("is:queued", ::Search::Queries::IssueQuery::field_list)
      state_merged      = ::Search::ParsletQuery.new("state:merged", ::Search::Queries::IssueQuery::field_list)
      state_draft       = ::Search::ParsletQuery.new("state:draft", ::Search::Queries::IssueQuery::field_list)
      is_draft          = ::Search::ParsletQuery.new("is:draft", ::Search::Queries::IssueQuery::field_list)
      type_pr           = ::Search::ParsletQuery.new("type:pr", ::Search::Queries::IssueQuery::field_list)
      type_pull_request = ::Search::ParsletQuery.new("type:pull-request", ::Search::Queries::IssueQuery::field_list)

      assert_equal Search::ParsletQuery::IndexType::PullRequest, is_pr.index_type
      assert_equal Search::ParsletQuery::IndexType::PullRequest, is_pull_request.index_type
      assert_equal Search::ParsletQuery::IndexType::PullRequest, is_merged.index_type
      assert_equal Search::ParsletQuery::IndexType::PullRequest, state_merged.index_type
      assert_equal Search::ParsletQuery::IndexType::PullRequest, state_draft.index_type
      assert_equal Search::ParsletQuery::IndexType::PullRequest, is_queued.index_type
      assert_equal Search::ParsletQuery::IndexType::PullRequest, is_draft.index_type
      assert_equal Search::ParsletQuery::IndexType::PullRequest, type_pr.index_type
      assert_equal Search::ParsletQuery::IndexType::PullRequest, type_pull_request.index_type
    end

    # nil assigns the default index type `issues-search`
    test "issues-search index type" do
      is_open     = ::Search::ParsletQuery.new("is:open", ::Search::Queries::IssueQuery::field_list)
      is_closed   = ::Search::ParsletQuery.new("is:closed", ::Search::Queries::IssueQuery::field_list)
      is_locked   = ::Search::ParsletQuery.new("is:locked", ::Search::Queries::IssueQuery::field_list)
      is_unlocked = ::Search::ParsletQuery.new("is:unlocked", ::Search::Queries::IssueQuery::field_list)
      is_public   = ::Search::ParsletQuery.new("is:public", ::Search::Queries::IssueQuery::field_list)
      is_private  = ::Search::ParsletQuery.new("is:private", ::Search::Queries::IssueQuery::field_list)

      assert_nil is_open.index_type
      assert_nil is_closed.index_type
      assert_nil is_locked.index_type
      assert_nil is_unlocked.index_type
      assert_nil is_public.index_type
    end

    test "issue or pr index type" do
      parser = ::Search::ParsletQuery.new("is:pr OR is:issue AND state:open", ::Search::Queries::IssueQuery::field_list)

      assert_nil parser.index_type # nil assigns the default index type `issues-search`
    end

    test "issue or issues index type" do
      parser = ::Search::ParsletQuery.new("is:issue OR is:issues AND state:open", ::Search::Queries::IssueQuery::field_list)

      assert_equal Search::ParsletQuery::IndexType::Issue, parser.index_type
    end

    test "pr or pull-request index type" do
      parser = ::Search::ParsletQuery.new("is:pr OR is:pull-request AND state:open", ::Search::Queries::IssueQuery::field_list)

      assert_equal Search::ParsletQuery::IndexType::PullRequest, parser.index_type
    end

    test "pr or pull-request or issues index type" do
      parser = ::Search::ParsletQuery.new("is:pr OR is:pull-request OR is:issues AND state:open", ::Search::Queries::IssueQuery::field_list)

      assert_nil parser.index_type # nil assigns the default index type `issues-search`
    end

    test "negative is: qualifier add the inverse index type" do
      parser = ::Search::ParsletQuery.new("-is:issue", ::Search::Queries::IssueQuery::field_list)

      assert_equal Search::ParsletQuery::IndexType::PullRequest, parser.index_type
    end

    test "negative type: qualifier add the inverse index type" do
      parser = ::Search::ParsletQuery.new("-type:issue", ::Search::Queries::IssueQuery::field_list)

      assert_equal Search::ParsletQuery::IndexType::PullRequest, parser.index_type
    end

    test "negative is: qualifier with OR inverse is: add the same index type" do
      parser = ::Search::ParsletQuery.new("-is:pr OR is:issue", ::Search::Queries::IssueQuery::field_list)

      assert_equal Search::ParsletQuery::IndexType::Issue, parser.index_type
    end

    test "nagative is: or type: can add both indices" do
      parser = ::Search::ParsletQuery.new("(-is:issue label:test) OR (-is:pr label:p1)", ::Search::Queries::IssueQuery::field_list)

      assert_nil parser.index_type
    end

    test "type pr or type epic index type" do
      parser = ::Search::ParsletQuery.new("type:pr OR type:Epic AND state:open", ::Search::Queries::IssueQuery::field_list)

      assert_nil parser.index_type # nil assigns the default index type `issues-search`
    end

    test "type issue or type task index type" do
      parser = ::Search::ParsletQuery.new("type:issue OR type:Task AND state:open", ::Search::Queries::IssueQuery::field_list)

      assert_equal Search::ParsletQuery::IndexType::Issue, parser.index_type
    end

    test "sets index to Issues if linked:pr and :type nil" do
      parser = ::Search::ParsletQuery.new("linked:pr label:a", ::Search::Queries::IssueQuery::field_list)

      assert_equal Search::ParsletQuery::IndexType::Issue, parser.index_type
    end

    test "sets index to PullRequests if linked:issue and :type nil" do
      parser = ::Search::ParsletQuery.new("linked:issue label:a", ::Search::Queries::IssueQuery::field_list)

      assert_equal Search::ParsletQuery::IndexType::PullRequest, parser.index_type
    end

    test "sets index to nil if linked:issue and linked:pr and :type nil" do
      parser = ::Search::ParsletQuery.new("linked:issue AND linked:pr label:a", ::Search::Queries::IssueQuery::field_list)

      refute parser.index_type
    end

    test "Sets index to nil if linked:issue and :type not nil" do
      parser = ::Search::ParsletQuery.new("type:issue linked:issue label:a", ::Search::Queries::IssueQuery::field_list)

      refute parser.index_type
    end
  end

  context "commas separated" do
    test "enumerable terms for label" do
      expected = build_single_term_qualifier(:label, %w[bug wontfix stale], false, true)
      parser = ::Search::ParsletQuery.new("label:bug,wontfix,stale", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP, enumerable_terms: [:label])
      assert_empty parser.query
      refute parser.complex?

      assert_equal %w[bug wontfix stale], parser.qualifiers[:label].and_should.flatten
      assert_equal expected, parser.conditional_qualifiers
    end

    test "enumerable terms for type" do
      expected = build_single_term_qualifier(:type, %w[bug epic task], false, true)

      parser = ::Search::ParsletQuery.new("type:bug,epic,task", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP, enumerable_terms: [:type])
      assert_empty parser.query
      refute parser.complex?

      assert_equal %w[bug epic task], parser.qualifiers[:type].and_should.flatten
      assert_equal expected, parser.conditional_qualifiers
    end

    test "negated enumerable terms for label" do
      expected = build_bool_qualifier(:and, [
        build_qualifier(:type, "issue"),
        build_qualifier(:label, %w[bug wontfix stale], true)
      ])
      parser = ::Search::ParsletQuery.new("is:issue -label:bug,wontfix,stale", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP, enumerable_terms: [:label])
      assert_empty parser.query
      refute parser.complex?

      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal %w[bug wontfix stale], parser.qualifiers[:label].must_not
      assert_equal expected, parser.conditional_qualifiers
    end

    test "negated enumerable terms for type" do
      expected = build_single_term_qualifier(:type, %w[bug epic], true)

      parser = ::Search::ParsletQuery.new("-type:bug,epic", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP, enumerable_terms: [:type])
      assert_empty parser.query
      refute parser.complex?

      assert_equal %w[bug epic], parser.qualifiers[:type].must_not
      assert_equal expected, parser.conditional_qualifiers
    end

    test "enumerable values with quotes" do
      expected = build_single_term_qualifier(:label, %w[API Bug], false, true)
      parser = ::Search::ParsletQuery.new('label:API,"Bug"', ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP, enumerable_terms: [:label])
      assert_empty parser.query
      refute parser.complex?

      assert_equal %w[API Bug], parser.qualifiers[:label].and_should.flatten
      assert_equal expected, parser.conditional_qualifiers
    end
  end

  test "has value qualifier" do
    parser = ::Search::ParsletQuery.new("has:milestones", ::Search::Queries::IssueQuery::field_list, presence_value_fields: ::Search::Queries::ConditionalIssueQuery::PRESENCE_VALUE_FIELDS)
    expected = build_qualifier(:milestone, :exists)

    refute parser.complex?
    assert_empty parser.query
    assert_equal build_single_term_qualifier(:milestone, :exists), parser.conditional_qualifiers
    assert_equal [:exists], parser.qualifiers[:milestone].must
  end

  test "has assignee" do
    parser = ::Search::ParsletQuery.new(
      "has:assignee",
      ::Search::Queries::IssueQuery::field_list,
      is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP,
      presence_value_fields: ::Search::Queries::ConditionalIssueQuery::PRESENCE_VALUE_FIELDS,
    )

    assert_equal [:exists], parser.qualifiers[:assignee].must
  end

  test "has:project" do
    query = Search::Queries::ConditionalIssueQuery.new(phrase: "has:project", current_user: @searcher)

    expected_query = {
      bool: {
        must: {
          bool: {
            should: [
              { exists: { field: "project_ids" } },
              { exists: { field: "memex_project_ids" } },
            ]
          }
        }
      }
    }

    assert_equal expected_query, query.build_query_filter[:bool][:must][1]
  end

  test "has filtered ignored with unsupported fields " do
    parser = ::Search::ParsletQuery.new(
      "has:notavalidvalue",
      ::Search::Queries::IssueQuery::field_list,
      is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP,
      presence_value_fields: ::Search::Queries::ConditionalIssueQuery::PRESENCE_VALUE_FIELDS,
    )

    assert_empty parser.qualifiers
  end


  test "no value qualifier" do
    parser = ::Search::ParsletQuery.new("no:milestones", ::Search::Queries::IssueQuery::field_list, presence_value_fields: ::Search::Queries::ConditionalIssueQuery::PRESENCE_VALUE_FIELDS)
    expected = build_qualifier(:milestone, :missing)

    refute parser.complex?
    assert_empty parser.query
    assert_equal build_single_term_qualifier(:milestone, :missing), parser.conditional_qualifiers
    assert_equal [:missing], parser.qualifiers[:milestone].must
  end

  test "type qualifiers for issue OR pr" do
    parser = ::Search::ParsletQuery.new("type:issue OR type:pr", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)
    expected = build_bool_qualifier(:or, [
      build_qualifier(:type, "issue"),
      build_qualifier(:type, "pr")
    ])

    assert parser.complex?
    assert_equal %w[issue pr], parser.qualifiers[:type].must
    assert_equal expected, parser.conditional_qualifiers
  end

  context "is_qualifier_map" do
    test "maps field found in the list" do
      parser = ::Search::ParsletQuery.new("is:issue", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      assert_equal ["issue"], parser.qualifiers[:type].must
      assert_equal build_single_term_qualifier(:type, "issue"), parser.conditional_qualifiers
    end

    test "maps draft when feature flag is enabled" do
      GitHub.flipper[:reviewable_state_searching].enable
      parser = ::Search::ParsletQuery.new("is:draft", ::Search::Queries::IssueQuery::field_list, current_user: create(:user))

      assert_equal ["draft"], parser.qualifiers[:"reviewable-state"].must
      assert_equal build_single_term_qualifier(:"reviewable-state", "draft"), parser.conditional_qualifiers
    end

    test "maps draft when feature flag is disabled" do
      GitHub.flipper[:reviewable_state_searching].disable
      parser = ::Search::ParsletQuery.new("is:draft", ::Search::Queries::IssueQuery::field_list, current_user: create(:user))

      assert_equal [true], parser.qualifiers[:draft].must
      assert_equal build_single_term_qualifier(:draft, true), parser.conditional_qualifiers
    end

    test "falls back to label when field is not found in the list" do
      parser = ::Search::ParsletQuery.new("is:testing", ::Search::Queries::IssueQuery::field_list, current_user: create(:user))

      assert_equal ["testing"], parser.qualifiers[:label].must
      assert_equal build_single_term_qualifier(:label, "testing"), parser.conditional_qualifiers
    end
  end

  context "implied user and repo filters" do
    test "transforms @user mention term into a filter" do
      parser = ::Search::ParsletQuery.new("@github", ::Search::Queries::IssueQuery::field_list)

      assert_empty parser.query
      assert_equal ["github"], parser.qualifiers[:user].must
      assert_equal build_single_term_qualifier(:user, "github"), parser.conditional_qualifiers
    end

    test "transforms @repo mention term into a filter" do
      parser = ::Search::ParsletQuery.new("@github/test.01", ::Search::Queries::IssueQuery::field_list)

      assert_empty parser.query
      assert_equal ["github/test.01"], parser.qualifiers[:repo].must
      assert_equal build_single_term_qualifier(:repo, "github/test.01"), parser.conditional_qualifiers
    end

    test "transforms @user and @repo mention terms into filters" do
      parser = ::Search::ParsletQuery.new("@github @github/test", ::Search::Queries::IssueQuery::field_list)

      assert_empty parser.query
      assert_equal ["github"], parser.qualifiers[:user].must
      assert_equal ["github/test"], parser.qualifiers[:repo].must
      assert_equal build_bool_qualifier(:and, [
        build_qualifier(:user, "github"),
        build_qualifier(:repo, "github/test"),
      ]), parser.conditional_qualifiers
    end

    test "transforms @user mention term in the middle of other filters" do
      parser = ::Search::ParsletQuery.new("is:issue @github label:bug", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      assert_empty parser.query
      assert_equal ["issue"], parser.qualifiers[:is].must
      assert_equal ["github"], parser.qualifiers[:user].must
      assert_equal ["bug"], parser.qualifiers[:label].must
      assert_equal build_bool_qualifier(:and, [
        build_qualifier(:type, "issue"),
        build_qualifier(:user, "github"),
        build_qualifier(:label, "bug"),
      ]), parser.conditional_qualifiers
    end

    test "transforms @repo mention term in the middle of other filters" do
      parser = ::Search::ParsletQuery.new("is:issue @github/test label:bug", ::Search::Queries::IssueQuery::field_list, is_qualifier_map: ::Search::Queries::ConditionalIssueQuery::IS_QUALIFIER_MAP)

      assert_empty parser.query
      assert_equal ["issue"], parser.qualifiers[:is].must
      assert_equal ["github/test"], parser.qualifiers[:repo].must
      assert_equal ["bug"], parser.qualifiers[:label].must
      assert_equal build_bool_qualifier(:and, [
        build_qualifier(:type, "issue"),
        build_qualifier(:repo, "github/test"),
        build_qualifier(:label, "bug"),
      ]), parser.conditional_qualifiers
    end

    test "combines a @user mention term and user: filter" do
      parser = ::Search::ParsletQuery.new("@github user:monalisa", ::Search::Queries::IssueQuery::field_list)

      assert_empty parser.query
      assert_equal %w[github monalisa], parser.qualifiers[:user].must
      assert_equal build_bool_qualifier(:and, [
        build_qualifier(:user, "github"),
        build_qualifier(:user, "monalisa"),
      ]), parser.conditional_qualifiers
    end

    test "combines a @repo mention term and repo: filter" do
      parser = ::Search::ParsletQuery.new("@github/test repo:monalisa/test", ::Search::Queries::IssueQuery::field_list)
      assert_empty parser.query
      assert_equal ["github/test", "monalisa/test"], parser.qualifiers[:repo].must
      assert_equal build_bool_qualifier(:and, [
        build_qualifier(:repo, "github/test"),
        build_qualifier(:repo, "monalisa/test"),
      ]), parser.conditional_qualifiers
    end

    test "transforms a negative @user mention into a negative user: filter" do
      parser = ::Search::ParsletQuery.new("-@monalisa", ::Search::Queries::IssueQuery::field_list)

      assert_empty parser.query
      assert_equal ["monalisa"], parser.qualifiers[:user].must_not
      assert_equal build_single_term_qualifier(:user, "monalisa", true), parser.conditional_qualifiers
    end

    test "transforms a negative @repo mention into a negative repo: filter" do
      parser = ::Search::ParsletQuery.new("-@github/test", ::Search::Queries::IssueQuery::field_list)

      assert_empty parser.query
      assert_equal ["github/test"], parser.qualifiers[:repo].must_not
      assert_equal build_single_term_qualifier(:repo, "github/test", true), parser.conditional_qualifiers
    end
  end

  test "accepts emoticon" do
    expected = build_single_term_qualifier(:label, "☃")

    parser = ::Search::ParsletQuery.new("label:☃", ::Search::Queries::IssueQuery::field_list)

    assert_equal ["☃"], parser.qualifiers[:label].must
    assert_equal expected, parser.conditional_qualifiers
  end

  test "accepts emoticon with space" do
    expected = build_single_term_qualifier(:label, "☃ bugs")
    parser = ::Search::ParsletQuery.new('label:"☃ bugs"', ::Search::Queries::IssueQuery::field_list)

    assert_equal ["☃ bugs"], parser.qualifiers[:label].must
    assert_equal expected, parser.conditional_qualifiers
  end

  test "values with a colon" do
    parser = ::Search::ParsletQuery.new(":rainbow: :ice_skate: onboarding", ::Search::Queries::IssueQuery::field_list)

    assert_equal ":rainbow: :ice_skate: onboarding", parser.query
  end

  test "unmatched quotes is handled as a string" do
    parser = ::Search::ParsletQuery.new('"chart library', ::Search::Queries::IssueQuery::field_list)

    assert_equal "chart library", parser.query
  end

  test "accepts quotes with space" do
    expected = build_bool_qualifier(:and, [
      build_qualifier(:state, "open"),
      build_qualifier(:label, "progressive enhancement")
    ])

    parser = ::Search::ParsletQuery.new('state:open label:"progressive enhancement"', ::Search::Queries::IssueQuery::field_list)

    assert_equal ["open"], parser.qualifiers[:state].must
    assert_equal ["progressive enhancement"], parser.qualifiers[:label].must
    assert_equal expected, parser.conditional_qualifiers
  end

  test "parses out aggregation qualifiers from the main query" do
    # The conditional query does not contain the aggregation term state:open
    # It is parsed out separately in `aggregation_qualifiers`
    expected = build_bool_qualifier(:and, [
      build_qualifier(:label, "bug")
    ])
    parser = ::Search::ParsletQuery.new("state:open label:bug", ::Search::Queries::IssueQuery::field_list, aggregation_fields: ::Search::Queries::ConditionalIssueQuery::AGGREGATION_FIELDS)
    assert_equal 1, parser.aggregation_qualifiers.length
    assert_equal ["open"], parser.aggregation_qualifiers[:state].must
    assert_equal expected, parser.conditional_qualifiers
  end

  private

  def build_qualifier(field, value, negative = false, enumerable = false)
    collection = ::Search::ParsedQuery::BoolCollection.new(field)

    if negative
      collection.must_not(value)
    elsif enumerable
      collection.and_should(value)
    else
      collection.must(value)
    end

    ::Search::ParsletQuery::Qualifier.new(field: field, collection: collection)
  end

  def build_bool_qualifier(type, qualifiers)
    ::Search::ParsletQuery::BoolQualifier.new(type: type, qualifiers: qualifiers)
  end

  def build_query_qualifier(query)
    ::Search::ParsletQuery::QueryQualifier.new(query: query)
  end

  def build_single_term_qualifier(field, value, negative = false, enumerable = false)
    build_bool_qualifier(:and, [build_qualifier(field, value, negative, enumerable)])
  end
end
