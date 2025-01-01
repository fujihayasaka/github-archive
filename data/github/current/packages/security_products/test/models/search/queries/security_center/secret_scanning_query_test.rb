# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesSecurityCenterSecretScanningQueryTest < GitHub::TestCase
  SecretScanningQuery = Search::Queries::SecurityCenter::SecretScanningQuery
  RESULTS_CATEGORY_QUALIFIER = Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY

  fixtures do
    @query_parser = Search::Queries::SecurityCenter::SecretScanningQuery
  end

  context "get_service_enums_from_slug_values" do
    test "gets enums when valid slug value" do
      enums = @query_parser.get_service_enums_from_slug_values("sort:created-asc,updated-desc", :"sort", @query_parser.sort_options)
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_ASCENDING, GitHub::Proto::SecretScanning::Api::V2::SortOrder::UPDATED_DESCENDING], enums
    end

    test "returns empty array if invalid slug value" do
      enums = @query_parser.get_service_enums_from_slug_values("sort:bad-slug", :"sort", @query_parser.sort_options)
      assert_equal [], enums
    end
  end

  test "handles empty query string" do
    q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "")
    assert_equal [], q.alert_states
    assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenState::NO_STATE], q.alert_state_enums
    refute q.is_open_page?
    assert_empty q.owners
    assert_empty q.repository_names
    assert_empty q.secret_types
    assert_empty q.secret_providers
    assert_empty q.resolutions
    assert_empty q.resolutions_enums
    assert_empty q.validities
    assert_empty q.validities_enums
    assert_empty q.bypassed
    assert_empty q.bypassed_enums
    assert_equal Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS_CATEGORY, q.results_category
    refute q.has_invalid_results_category?
    assert_nil q.sort
    assert_equal GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_DESCENDING, q.sort_enum
  end

  context "#is_valid?" do
    test "empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "")
      assert q.is_valid?
    end

    test "unqualified terms" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "foo")
      refute q.is_valid?
    end

    test "unknown qualifier" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "foo:bar")
      refute q.is_valid?
    end

    context "invalid state queries" do
      test_cases = [
        "is:fake",
        "-is:purple",
        "-is:open",
        "-is:closed",
        "-is:open,closed",
        "-is:publicly-leaked",
        "-is:open,publicly-leaked",
        "-is:open,multi-repository",
        "-is:closed,publicly-leaked",
        "-is:closed,multi-repository",
      ]
      test_cases.each do |query|
        test query do
          q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query:)
          refute q.is_valid?
        end
      end
    end

    test "invalid resolutions" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "resolution:bad-resolution")
      refute q.is_valid?
    end

    test "duplicate qualifiers" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:open is:closed")
      refute q.is_valid?
    end

    context "supports special is:publicly-leaked qualifier" do
      test_cases = [
        "is:open,publicly-leaked",
        "is:publicly-leaked,open",
        "is:open is:publicly-leaked",
        "is:publicly-leaked is:open",
        "is:open is_publicly_leaked:true",
        "is_publicly_leaked:true is:open",
      ]
      test_cases.each do |query|
        test query do
          q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query:)
          assert q.is_valid?
          assert q.is_open_page?
          assert q.has_valid_publicly_leaked?
        end
      end
    end

    context "supports special is:multi-repository qualifier" do
      test_cases = [
        "is:open,multi-repository",
        "is:multi-repository,open",
        "is:open is:multi-repository",
        "is:multi-repository is:open",
        "is:open is_multi_repository:true",
        "is_multi_repository:true is:open",
      ]
      test_cases.each do |query|
        test query do
          q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query:)
          assert q.is_valid?
          assert q.is_open_page?
          assert q.has_valid_multi_repository?
        end
      end
    end

    test "invalid when is_publicly_leaked:false" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:open is_publicly_leaked:false")
      refute q.is_valid?
      refute q.has_valid_publicly_leaked?
    end

    test "invalid when is_multi_repository:false" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:open is_multi_repository:false")
      refute q.is_valid?
      refute q.has_valid_multi_repository?
    end

    test "empty value" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:")
      refute q.is_valid?
    end

    test "invalid results category" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "#{RESULTS_CATEGORY_QUALIFIER}:blah")
      refute q.is_valid?
    end

    test "invalid validity" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "validity:blah")
      refute q.is_valid?
    end

    test "invalid bypassed" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "bypassed:blah")
      refute q.is_valid?
    end
  end

  context "#alert_states" do
    test "when state is set to open return an open alert state" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:open")
      assert_equal ["open"], q.alert_states
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenState::OPEN], q.alert_state_enums
      assert q.is_open_page?
    end

    test "when state is set to closed return an closed alert state" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:closed")
      assert_equal ["closed"], q.alert_states
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenState::RESOLVED], q.alert_state_enums
      refute q.is_open_page?
      refute q.is_no_state_page?
    end

    test "when multiple state qualifiers are provided treat it as a NO_STATE page" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:open is:closed")
      assert_equal %w[open closed], q.alert_states
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenState::OPEN, GitHub::Proto::SecretScanning::Api::V2::TokenState::RESOLVED], q.alert_state_enums
      assert q.is_no_state_page?

      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:closed is:open")
      assert_equal %w[closed open], q.alert_states
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenState::RESOLVED, GitHub::Proto::SecretScanning::Api::V2::TokenState::OPEN], q.alert_state_enums
      assert q.is_no_state_page?
    end

    test "when multiple comma separated values are provided treat it as a NO_STATE page" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:closed,open")
      assert_equal %w[closed open], q.alert_states
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenState::RESOLVED, GitHub::Proto::SecretScanning::Api::V2::TokenState::OPEN], q.alert_state_enums
      assert q.is_no_state_page?

      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:open,closed")
      assert_equal %w[open closed], q.alert_states
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenState::OPEN, GitHub::Proto::SecretScanning::Api::V2::TokenState::RESOLVED], q.alert_state_enums
      assert q.is_no_state_page?
    end

    test "when an empty value is provided return NO_STATE" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:")
      assert_equal [], q.alert_states
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenState::NO_STATE], q.alert_state_enums
      refute q.is_open_page?
      assert q.is_no_state_page?
    end

    test "when a blank query is provided return NO_STATE" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "")
      assert_equal [], q.alert_states
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenState::NO_STATE], q.alert_state_enums
      refute q.is_open_page?
      assert q.is_no_state_page?
    end

    test "when both states are provided treat it as a NO_STATE page" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:open,closed")
      expected_state_enums = [GitHub::Proto::SecretScanning::Api::V2::TokenState::OPEN, GitHub::Proto::SecretScanning::Api::V2::TokenState::RESOLVED]
      assert_equal %w[open closed], q.alert_states
      assert_equal expected_state_enums, q.alert_state_enums
      assert q.is_no_state_page?
    end

    test "when a unsupported value is provided return NO_STATE" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "is:foo")
      assert_equal ["foo"], q.alert_states
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenState::NO_STATE], q.alert_state_enums
      refute q.is_open_page?
      assert q.is_no_state_page?
    end
  end

  context "#owner" do
    test "single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "owner:foo")
      assert_equal ["foo"], q.owners
    end

    test "multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "owner:foo owner:bar")
      assert_equal %w[foo bar], q.owners
    end

    test "multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "owner:foo,bar")
      assert_equal %w[foo bar], q.owners
    end

    test "empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "owner:")
      assert_empty q.owners
    end

    test "negate single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-owner:foo")
      assert_equal ["foo"], q.negated_owners
    end

    test "negate multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-owner:foo -owner:bar")
      assert_equal %w[foo bar], q.negated_owners
    end

    test "negate multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-owner:foo,bar")
      assert_equal %w[foo bar], q.negated_owners
    end

    test "negate empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-owner:")
      assert_empty q.negated_owners
    end

    test "mixed negation" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "owner:foo -owner:bar")
      assert_equal ["foo"], q.owners
      assert_equal ["bar"], q.negated_owners

      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-owner:foo owner:bar")
      assert_equal ["bar"], q.owners
      assert_equal ["foo"], q.negated_owners
    end
  end

  context "#repo" do
    test "single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "repo:foo")
      assert_equal ["foo"], q.repository_names
    end

    test "multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "repo:foo repo:bar")
      assert_equal %w[foo bar], q.repository_names
    end

    test "multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "repo:foo,bar")
      assert_equal %w[foo bar], q.repository_names
    end

    test "empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "repo:")
      assert_empty q.repository_names
    end

    test "negate single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-repo:foo")
      assert_equal ["foo"], q.negated_repository_names
    end

    test "negate multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-repo:foo -repo:bar")
      assert_equal %w[foo bar], q.negated_repository_names
    end

    test "negate multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-repo:foo,bar")
      assert_equal %w[foo bar], q.negated_repository_names
    end

    test "negate empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-repo:")
      assert_empty q.negated_repository_names
    end

    test "mixed negation" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "repo:foo -repo:bar")
      assert_equal ["foo"], q.repository_names
      assert_equal ["bar"], q.negated_repository_names

      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-repo:foo repo:bar")
      assert_equal ["bar"], q.repository_names
      assert_equal ["foo"], q.negated_repository_names
    end
  end

  context "#team" do
    test "single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "team:foo")
      assert_equal ["foo"], q.team_names
    end

    test "multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "team:foo team:bar")
      assert_equal %w[foo bar], q.team_names
    end

    test "multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "team:foo,bar")
      assert_equal %w[foo bar], q.team_names
    end

    test "empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "team:")
      assert_empty q.team_names
    end

    test "negate single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-team:foo")
      assert_equal ["foo"], q.negated_team_names
    end

    test "negate multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-team:foo -team:bar")
      assert_equal %w[foo bar], q.negated_team_names
    end

    test "negate multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-team:foo,bar")
      assert_equal %w[foo bar], q.negated_team_names
    end

    test "negate empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-team:")
      assert_empty q.negated_team_names
    end

    test "mixed negation" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "team:foo -team:bar")
      assert_equal ["foo"], q.team_names
      assert_equal ["bar"], q.negated_team_names

      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-team:foo team:bar")
      assert_equal ["bar"], q.team_names
      assert_equal ["foo"], q.negated_team_names
    end
  end

  context "#topic" do
    test "single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "topic:foo")
      assert_equal ["foo"], q.topics
    end

    test "multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "topic:foo topic:bar")
      assert_equal %w[foo bar], q.topics
    end

    test "multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "topic:foo,bar")
      assert_equal %w[foo bar], q.topics
    end

    test "empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "topic:")
      assert_empty q.topics
    end

    test "negate single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-topic:foo")
      assert_equal ["foo"], q.negated_topics
    end

    test "negate multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-topic:foo -topic:bar")
      assert_equal %w[foo bar], q.negated_topics
    end

    test "negate multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-topic:foo,bar")
      assert_equal %w[foo bar], q.negated_topics
    end

    test "negate empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-topic:")
      assert_empty q.negated_topics
    end

    test "mixed negation" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "topic:foo -topic:bar")
      assert_equal ["foo"], q.topics
      assert_equal ["bar"], q.negated_topics

      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-topic:foo topic:bar")
      assert_equal ["bar"], q.topics
      assert_equal ["foo"], q.negated_topics
    end
  end

  context "#secret_type" do
    test "single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "secret-type:foo")
      assert_equal ["foo"], q.secret_types
    end

    test "multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "secret-type:foo secret-type:bar")
      assert_equal %w[foo bar], q.secret_types
    end

    test "multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "secret-type:foo,bar")
      assert_equal %w[foo bar], q.secret_types
    end

    test "empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "secret-type:")
      assert_empty q.secret_types
    end

    test "negate single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-secret-type:foo")
      assert_equal ["foo"], q.negated_secret_types
    end

    test "negate multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-secret-type:foo -secret-type:bar")
      assert_equal %w[foo bar], q.negated_secret_types
    end

    test "negate multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-secret-type:foo,bar")
      assert_equal %w[foo bar], q.negated_secret_types
    end

    test "negate empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-secret-type:")
      assert_empty q.negated_secret_types
    end

    test "mixed negation" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "secret-type:foo -secret-type:bar")
      assert_equal ["foo"], q.secret_types
      assert_equal ["bar"], q.negated_secret_types

      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-secret-type:foo secret-type:bar")
      assert_equal ["bar"], q.secret_types
      assert_equal ["foo"], q.negated_secret_types
    end
  end

  context "#provider" do
    test "single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "provider:foo")
      assert_equal ["foo"], q.secret_providers
    end

    test "multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "provider:foo provider:bar")
      assert_equal %w[foo bar], q.secret_providers
    end

    test "multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "provider:foo,bar")
      assert_equal %w[foo bar], q.secret_providers
    end

    test "empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "provider:")
      assert_empty q.secret_providers
    end

    test "underscore" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "provider:foo_bar")
      assert_equal ["foo bar"], q.secret_providers
    end

    test "multiple underscores" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "provider:foo_bar_test")
      assert_equal ["foo bar test"], q.secret_providers
    end

    test "quoted space" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "provider:\"foo bar\"")
      assert_equal ["foo bar"], q.secret_providers
    end

    test "negate single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-provider:foo")
      assert_equal ["foo"], q.negated_secret_providers
    end

    test "negate multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-provider:foo -provider:bar")
      assert_equal %w[foo bar], q.negated_secret_providers
    end

    test "negate multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-provider:foo,bar")
      assert_equal %w[foo bar], q.negated_secret_providers
    end

    test "negate empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-provider:")
      assert_empty q.negated_secret_providers
    end

    test "negate underscore" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-provider:foo_bar")
      assert_equal ["foo bar"], q.negated_secret_providers
    end

    test "mixed negation" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "provider:foo -provider:bar")
      assert_equal ["foo"], q.secret_providers
      assert_equal ["bar"], q.negated_secret_providers

      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-provider:foo provider:bar")
      assert_equal ["bar"], q.secret_providers
      assert_equal ["foo"], q.negated_secret_providers
    end
  end

  context "#resolution" do
    test "single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "resolution:revoked")
      assert_equal ["revoked"], q.resolutions
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED
      ], q.resolutions_enums
      assert_equal [
        "REVOKED"
      ], q.resolutions_strings
    end

    test "multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "resolution:wont-fix resolution:false-positive")
      assert_equal %w[wont-fix false-positive], q.resolutions
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::WONT_FIX,
        GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE,
      ], q.resolutions_enums
      assert_equal %w[
        WONT_FIX
        FALSE_POSITIVE
      ], q.resolutions_strings
    end

    test "multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "resolution:used-in-tests,pattern-deleted")
      assert_equal %w[used-in-tests pattern-deleted], q.resolutions
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::USED_IN_TESTS,
        GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::PATTERN_DELETED,
      ], q.resolutions_enums
      assert_equal %w[
        USED_IN_TESTS
        PATTERN_DELETED
      ], q.resolutions_strings
    end

    test "empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "resolution:")
      assert_empty q.resolutions
      assert_empty q.resolutions_enums
      assert_empty q.resolutions_strings
    end

    test "out of range" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "resolution:foo")
      assert_equal ["foo"], q.resolutions
      assert_empty q.resolutions_enums
      assert_empty q.resolutions_strings
    end

    test "negate single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-resolution:revoked")
      assert_equal ["revoked"], q.negated_resolutions
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED
      ], q.negated_resolutions_enums
      assert_equal [
        "REVOKED"
      ], q.negated_resolutions_strings
    end

    test "negate multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-resolution:wont-fix -resolution:false-positive")
      assert_equal %w[wont-fix false-positive], q.negated_resolutions
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::WONT_FIX,
        GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::FALSE_POSITIVE,
      ], q.negated_resolutions_enums
      assert_equal %w[
        WONT_FIX
        FALSE_POSITIVE
      ], q.negated_resolutions_strings
    end

    test "negate multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-resolution:used-in-tests,pattern-deleted")
      assert_equal %w[used-in-tests pattern-deleted], q.negated_resolutions
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::USED_IN_TESTS,
        GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::PATTERN_DELETED,
      ], q.negated_resolutions_enums
      assert_equal %w[
        USED_IN_TESTS
        PATTERN_DELETED
      ], q.negated_resolutions_strings
    end

    test "negate empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-resolution:")
      assert_empty q.negated_resolutions
      assert_empty q.negated_resolutions_enums
      assert_empty q.negated_resolutions_strings
    end

    test "negate out of range" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-resolution:foo")
      assert_equal ["foo"], q.negated_resolutions
      assert_empty q.negated_resolutions_enums
      assert_empty q.negated_resolutions_strings
    end

    test "mixed negation" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "resolution:revoked -resolution:wont-fix")
      assert_equal ["revoked"], q.resolutions
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED], q.resolutions_enums
      assert_equal ["REVOKED"], q.resolutions_strings
      assert_equal ["wont-fix"], q.negated_resolutions
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::WONT_FIX], q.negated_resolutions_enums
      assert_equal ["WONT_FIX"], q.negated_resolutions_strings

      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-resolution:revoked resolution:wont-fix")
      assert_equal ["wont-fix"], q.resolutions
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::WONT_FIX], q.resolutions_enums
      assert_equal ["revoked"], q.negated_resolutions
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::REVOKED], q.negated_resolutions_enums
    end
  end

  context "#validity" do
    test "single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "validity:active")
      assert_equal ["active"], q.validities
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_ACTIVE
      ], q.validities_enums
      assert_equal [
        "TOKEN_VALIDITY_ACTIVE"
      ], q.validities_strings
    end

    test "multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "validity:unknown validity:inactive")
      assert_equal %w[unknown inactive], q.validities
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_UNKNOWN,
        GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_INACTIVE,
      ], q.validities_enums
      assert_equal %w[
        TOKEN_VALIDITY_UNKNOWN
        TOKEN_VALIDITY_INACTIVE
      ], q.validities_strings
    end

    test "multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "validity:active,inactive")
      assert_equal %w[active inactive], q.validities
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_ACTIVE,
        GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_INACTIVE,
      ], q.validities_enums
      assert_equal %w[
        TOKEN_VALIDITY_ACTIVE
        TOKEN_VALIDITY_INACTIVE
      ], q.validities_strings
    end

    test "empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "validity:")
      assert_empty q.validities
      assert_empty q.validities_enums
      assert_empty q.validities_strings
    end

    test "out of range" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "validity:foo")
      assert_equal ["foo"], q.validities
      assert_empty q.validities_enums
      assert_empty q.validities_strings
    end

    test "negate single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-validity:active")
      assert_equal ["active"], q.negated_validities
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_ACTIVE
      ], q.negated_validities_enums
      assert_equal [
        "TOKEN_VALIDITY_ACTIVE"
      ], q.negated_validities_strings
    end

    test "negate multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-validity:unknown -validity:inactive")
      assert_equal %w[unknown inactive], q.negated_validities
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_UNKNOWN,
        GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_INACTIVE
      ], q.negated_validities_enums
      assert_equal %w[
        TOKEN_VALIDITY_UNKNOWN
        TOKEN_VALIDITY_INACTIVE
      ], q.negated_validities_strings
    end

    test "negate multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-validity:active,inactive")
      assert_equal %w[active inactive], q.negated_validities
      assert_equal [
        GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_ACTIVE,
        GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_INACTIVE,
      ], q.negated_validities_enums
      assert_equal %w[
        TOKEN_VALIDITY_ACTIVE
        TOKEN_VALIDITY_INACTIVE
      ], q.negated_validities_strings
    end

    test "negate empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-validity:")
      assert_empty q.negated_validities
      assert_empty q.negated_validities_enums
      assert_empty q.negated_validities_strings
    end

    test "negate out of range" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-validity:foo")
      assert_equal ["foo"], q.negated_validities
      assert_empty q.negated_validities_enums
      assert_empty q.negated_validities_strings
    end

    test "mixed negation" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "validity:revoked -validity:inactive")
      assert_equal ["inactive"], q.negated_validities
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_INACTIVE], q.negated_validities_enums
      assert_equal ["TOKEN_VALIDITY_INACTIVE"], q.negated_validities_strings

      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-validity:revoked validity:inactive")
      assert_equal ["inactive"], q.validities
      assert_equal [GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_INACTIVE], q.validities_enums
    end
  end

  context "#bypassed" do
    test "single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "bypassed:true")
      assert_equal ["true"], q.bypassed
      assert_equal [
        Search::Queries::SecurityCenter::SecretScanningQuery::BYPASSED_TRUE_ENUM
      ], q.bypassed_enums
      assert_equal [
        "true"
      ], q.bypassed_strings
    end

    test "empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "bypassed:")
      assert_empty q.bypassed
      assert_empty q.bypassed_enums
      assert_empty q.bypassed_strings
    end

    test "out of range" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "bypassed:foo")
      assert_equal ["foo"], q.bypassed
      assert_empty q.bypassed_enums
      assert_empty q.bypassed_strings
    end

    test "negate single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-bypassed:true")
      assert_equal ["true"], q.negated_bypassed
      assert_equal [
        Search::Queries::SecurityCenter::SecretScanningQuery::BYPASSED_TRUE_ENUM
      ], q.negated_bypassed_enums
      assert_equal [
        "true"
      ], q.negated_bypassed_strings
    end

    test "negate empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-bypassed:")
      assert_empty q.negated_bypassed
      assert_empty q.negated_bypassed_enums
      assert_empty q.negated_bypassed_strings
    end

    test "negate out of range" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "-bypassed:foo")
      assert_equal ["foo"], q.negated_bypassed
      assert_empty q.negated_bypassed_enums
      assert_empty q.negated_bypassed_strings
    end
  end

  context "#sort" do
    test "single" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "sort:updated-asc")
      assert_equal "updated-asc", q.sort
      assert_equal GitHub::Proto::SecretScanning::Api::V2::SortOrder::UPDATED_ASCENDING, q.sort_enum
    end

    test "multiple" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "sort:updated-asc sort:created-desc")
      assert_equal "updated-asc", q.sort
      assert_equal GitHub::Proto::SecretScanning::Api::V2::SortOrder::UPDATED_ASCENDING, q.sort_enum
    end

    test "multiple comma separated" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "sort:created-asc,updated-desc")
      assert_equal "created-asc", q.sort
      assert_equal GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_ASCENDING, q.sort_enum
    end

    test "empty" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "sort:")
      assert_nil q.sort
      assert_equal GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_DESCENDING, q.sort_enum
    end

    test "out of range" do
      q = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: "sort:foo-bar")
      assert_equal "foo-bar", q.sort
      assert_equal GitHub::Proto::SecretScanning::Api::V2::SortOrder::CREATED_DESCENDING, q.sort_enum
    end
  end

  context "get_is_state_href" do
    test "adds state to href" do
      href = @query_parser.new(query: "").get_is_state_href(Search::Queries::SecurityCenter::SecretScanningQuery::IS_OPEN)
      assert_equal "?query=#{CGI.escape("is:open")}", href
    end

    test "overrides state" do
      href = @query_parser.new(query: "is:closed").get_is_state_href(Search::Queries::SecurityCenter::SecretScanningQuery::IS_OPEN)
      assert_equal "?query=#{CGI.escape("is:open")}", href
    end

    test "keeps resolution" do
      query = "is:open resolution:wont-fix"
      href = @query_parser.new(query: query).get_is_state_href(Search::Queries::SecurityCenter::SecretScanningQuery::IS_OPEN)
      assert_equal "?query=#{CGI.escape(query)}", href
    end
  end

  context "#results" do
    test "default results" do
      conf = Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS_CATEGORY
      query = "#{RESULTS_CATEGORY_QUALIFIER}:#{conf}"
      q = @query_parser.new(query: query)
      assert_equal conf, q.results_category
      refute q.has_invalid_results_category?
    end

    test "generic results" do
      conf = Search::Queries::SecurityCenter::SecretScanningQuery::GENERIC_RESULTS
      query = "#{RESULTS_CATEGORY_QUALIFIER}:#{conf}"
      q = @query_parser.new(query: query)
      assert_equal conf, q.results_category
      refute q.has_invalid_results_category?
    end

    test "invalid results category" do
      query = "#{RESULTS_CATEGORY_QUALIFIER}:blah"
      q = @query_parser.new(query: query)
      assert q.has_invalid_results_category?
    end

    test "empty results_category" do
      query = "#{RESULTS_CATEGORY_QUALIFIER}:"
      q = @query_parser.new(query: query)
      assert_equal SecretScanningQuery::DEFAULT_RESULTS_CATEGORY, q.results_category
      refute q.has_invalid_results_category?
    end
  end

  context "get_results_category_href" do
    test "adds results_category to href" do
      href = @query_parser.new(query: "").get_results_category_href(SecretScanningQuery::DEFAULT_RESULTS_CATEGORY)
      assert_equal "?query=#{CGI.escape("#{RESULTS_CATEGORY_QUALIFIER}:#{SecretScanningQuery::DEFAULT_RESULTS_CATEGORY}")}", href
    end

    test "overrides results_category" do
      href = @query_parser.new(query: "#{RESULTS_CATEGORY_QUALIFIER}:#{SecretScanningQuery::GENERIC_RESULTS}").get_results_category_href(SecretScanningQuery::DEFAULT_RESULTS_CATEGORY)
      assert_equal "?query=#{CGI.escape("#{RESULTS_CATEGORY_QUALIFIER}:#{SecretScanningQuery::DEFAULT_RESULTS_CATEGORY}")}", href
    end

    test "keeps resolution" do
      query = "resolution:wont-fix"
      href = @query_parser.new(query: query).get_results_category_href(SecretScanningQuery::DEFAULT_RESULTS_CATEGORY)
      assert_equal "?query=#{CGI.escape("resolution:wont-fix #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{SecretScanningQuery::DEFAULT_RESULTS_CATEGORY}")}", href
    end
  end
end
