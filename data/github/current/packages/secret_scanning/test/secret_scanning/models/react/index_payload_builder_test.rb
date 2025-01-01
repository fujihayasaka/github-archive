# typed: true
# frozen_string_literal: true

require "test_helper"

class IndexPayloadBuilderTest < GitHub::TestCase
  QUERY_PARSER = Search::Queries::SecurityCenter::SecretScanningQuery
  include FineGrainedPermissionsTestHelper

  fixtures do
    @user = create(:user)
    @org = create(:business_plus_organization, admin: @user)
    @repo = create(:repository, owner: @org, from_example: :pull_request_fork)

    @issue = create(:issue, repository: @repo, number: 1)

    @pull_issue = create(:issue, user: @user, repository: @repo)
    @pull_request = create(:pull_request, repository: @repo, issue: @pull_issue, user: @user)

    @view_secret_scanning_alerts_user = create(:user, name: "view-secret-scanning-alerts-user")
    grant_custom_role(user: @view_secret_scanning_alerts_user, target: @repo, fgps: [:view_secret_scanning_alerts])

    @payload_builder = SecretScanning::Models::React::IndexPayloadBuilder.new(@repo, @user).freeze
  end

  setup do
    SecretScanning::Features::Repo::CustomPatterns.any_instance.stubs(:feature_available?).returns(true)
    SecretScanning::Features::Repo::TokenScanning.any_instance.stubs(:feature_available?).returns(true)

    @token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
      created_at: Time.parse("2022-10-21"),
      first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
      id: 1,
      label: "Adafruit IO Key",
      token_type: "adafruit_io_key",
      repository_id: @repo.id,
      number: 1,
    )
    @token = GitHub::TokenScanning::Service::Token.new(@token_from_api, @repo)
  end

  context "payload" do
    test "builds index page payload" do
      actual_payload = @payload_builder.page_payload([@token], 1, 0, "is:open", 25, 1, false, false, false)

      assert_equal 1, actual_payload[:open_alert_count]
      assert_equal 0, actual_payload[:closed_alert_count]

      actual_payload[:alerts].each do |alert|
        assert_equal SecretScanning::Models::Alert, alert.class
        assert_equal 1, alert.number
        assert_equal "Adafruit IO Key", alert.label
        assert_equal "adafruit_io_key", alert.token_type
      end

      assert_equal "none", actual_payload[:backfill_status]

      assert_equal "is:open", actual_payload[:query][:query_string]
      assert_equal "query=is%3Aopen", actual_payload[:query][:url]
      assert_equal true, actual_payload[:query][:is_open]
      assert_equal "is:open", actual_payload[:query][:is_open_query]
      assert_equal false, actual_payload[:query][:is_closed]
      assert_equal "is:closed", actual_payload[:query][:is_closed_query]

      sort_options = [
        {
          label: "Newest",
          slug: "created-desc",
          query: "is:open sort:created-desc",
          checked: true,
          excluded: false,
        },
        {
          label: "Oldest",
          slug: "created-asc",
          query: "is:open sort:created-asc",
          checked: false,
          excluded: false,
        },
        {
          label: "Recently updated",
          slug: "updated-desc",
          query: "is:open sort:updated-desc",
          checked: false,
          excluded: false,
        },
        {
          label: "Least recently updated",
          slug: "updated-asc",
          query: "is:open sort:updated-asc",
          checked: false,
          excluded: false,
        }
      ]
      assert_equal sort_options, actual_payload[:query][:sort_options]

      resolution_clear_all = {
        label: "Clear closure reasons",
        slug: nil,
        query: "is:open",
        checked: false,
        excluded: false,
        hidden: true,
      }
      assert_equal resolution_clear_all, actual_payload[:query][:resolution_clear_all]

      resolution_options = [
        {
          label: "Revoked",
          slug: "revoked",
          query: "is:open resolution:revoked",
          checked: false,
          excluded: false,
        },
        {
          label: "False positive",
          slug: "false-positive",
          query: "is:open resolution:false-positive",
          checked: false,
          excluded: false,
        },
        {
          label: "Used in tests",
          slug: "used-in-tests",
          query: "is:open resolution:used-in-tests",
          checked: false,
          excluded: false,
        },
        {
          label: "Won't fix",
          slug: "wont-fix",
          query: "is:open resolution:wont-fix",
          checked: false,
          excluded: false,
        },
        {
          label: "Custom pattern edited",
          slug: "pattern-edited",
          query: "is:open resolution:pattern-edited",
          checked: false,
          excluded: false,
        },
        {
          label: "Custom pattern deleted",
          slug: "pattern-deleted",
          query: "is:open resolution:pattern-deleted",
          checked: false,
          excluded: false,
        },
        {
          label: "Ignored by configuration",
          slug: "hidden-by-config",
          query: "is:open resolution:hidden-by-config",
          checked: false,
          excluded: false,
        },
      ]
      assert_equal resolution_options, actual_payload[:query][:resolution_options]
      assert_equal true, actual_payload[:resolve_alerts_allowed]
    end

    test "resolve alerts not allowed for view secret scanning alerts user" do
      payload = SecretScanning::Models::React::IndexPayloadBuilder.new(@repo, @view_secret_scanning_alerts_user)
      actual_payload = payload.page_payload([@token], 1, 0, "is:open", 25, 1, false, false, false)

      assert_equal false, T.must(actual_payload)[:resolve_alerts_allowed]
    end
  end

  context "backfill status" do
    test "returns none when all values false" do
      backfill_status = @payload_builder.send(:backfill_status, false, false, false)
      assert_equal SecretScanning::Models::React::BackfillStatusType::None, backfill_status
    end

    test "returns pending when pending true" do
      backfill_status = @payload_builder.send(:backfill_status, true, false, false)
      assert_equal SecretScanning::Models::React::BackfillStatusType::Pending, backfill_status
    end

    test "returns pending when pending and other values true" do
      backfill_status = @payload_builder.send(:backfill_status, true, true, true)
      assert_equal SecretScanning::Models::React::BackfillStatusType::Pending, backfill_status
    end

    test "returns terminal error when terminal error true" do
      backfill_status = @payload_builder.send(:backfill_status, false, true, false)
      assert_equal SecretScanning::Models::React::BackfillStatusType::TerminalError, backfill_status
    end

    test "returns max candidate when max candidates true" do
      backfill_status = @payload_builder.send(:backfill_status, false, false, true)
      assert_equal SecretScanning::Models::React::BackfillStatusType::MaxCandidates, backfill_status
    end
  end

  context "total pages" do
    test "returns 1 page when there are no alerts" do
      open_tokens = 0
      query = "is:open"

      actual_total_pages = @payload_builder.send(:get_total_pages, open_tokens, 3, query, Repos::SecretScanning::ReactAlertsController::PAGE_SIZE)

      assert_equal 1, actual_total_pages
    end

    test "returns 1 page when there's a single open alert selected" do
      open_tokens = 1
      query = "is:open"

      actual_total_pages = @payload_builder.send(:get_total_pages, open_tokens, 3, query, Repos::SecretScanning::ReactAlertsController::PAGE_SIZE)

      assert_equal 1, actual_total_pages
    end

    test "returns 2 pages when there's n + 1 open alerts" do
      open_tokens = Repos::SecretScanning::ReactAlertsController::PAGE_SIZE + 1
      query = "is:open"

      actual_total_pages = @payload_builder.send(:get_total_pages, open_tokens, 3, query, Repos::SecretScanning::ReactAlertsController::PAGE_SIZE)

      assert_equal 2, actual_total_pages
    end

    test "returns 2 pages when there's n * 2 open alerts" do
      open_tokens = Repos::SecretScanning::ReactAlertsController::PAGE_SIZE * 2
      query = "is:open"
      actual_total_pages = @payload_builder.send(:get_total_pages, open_tokens, 3, query, Repos::SecretScanning::ReactAlertsController::PAGE_SIZE)

      assert_equal 2, actual_total_pages
    end

    test "returns 2 pages when there's n + 1 closed alerts" do
      closed_tokens = Repos::SecretScanning::ReactAlertsController::PAGE_SIZE + 1
      query = "is:closed"

      actual_total_pages = @payload_builder.send(:get_total_pages, 5000, closed_tokens, query, Repos::SecretScanning::ReactAlertsController::PAGE_SIZE)

      assert_equal 2, actual_total_pages
    end

    test "returns 2 pages when there's n + 1 combined alerts" do
      open_tokens = Repos::SecretScanning::ReactAlertsController::PAGE_SIZE
      closed_tokens = 1
      query = ""

      actual_total_pages = @payload_builder.send(:get_total_pages, open_tokens, closed_tokens, query, Repos::SecretScanning::ReactAlertsController::PAGE_SIZE)

      assert_equal 2, actual_total_pages
    end

    test "returns 2 pages when there's n + 1 combined alerts and an unknown query" do
      open_tokens = Repos::SecretScanning::ReactAlertsController::PAGE_SIZE
      closed_tokens = 1
      query = "is:foo"

      actual_total_pages = @payload_builder.send(:get_total_pages, open_tokens, closed_tokens, query, Repos::SecretScanning::ReactAlertsController::PAGE_SIZE)

      assert_equal 2, actual_total_pages
    end
  end

  context "reverse_truncate_path" do
    test "2 directory levels no truncation properly" do
      result = @payload_builder.send(:reverse_truncate_path, "foo/bar/baz.md", 25)
      assert_equal "foo/bar/baz.md", result
    end

    test "several directory levels 25 chars max" do
      result = @payload_builder.send(:reverse_truncate_path, "1/2/3/testingtruncation/foo/bar/baz.md", 25)
      assert_equal "1/.../bar/baz.md", result
    end

    test "root directory level no elipses" do
      result = @payload_builder.send(:reverse_truncate_path, "readme.md", 25)
      assert_equal "readme.md", result
    end

    test "long directory names" do
      result = @payload_builder.send(:reverse_truncate_path, "really_long_root_directory/some/middle/directory/stuff/really_long_file_name.txt", 25)
      assert_equal "really_long_root_director.../.../stuff/really_long_file_name.txt", result
    end
    test "long file names" do
      result = @payload_builder.send(:reverse_truncate_path, "this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file_this_is_a_very_long_file.txt", 25)
      assert_equal "this_is_a_very_long_file_...", result
    end

    test "max path segment length" do
      result = @payload_builder.send(:reverse_truncate_path, "really_long_root_directory/stuff/really_long_file_name.txt", 8)
      assert_equal "really_l.../stuff/really_l...", result
    end

    test "max path segment length with deep nesting" do
      result = @payload_builder.send(:reverse_truncate_path, "really_long_root_directory/some/middle/directory/stuff/really_long_file_name.txt", 8)
      assert_equal "really_l.../.../stuff/really_l...", result
    end
  end

  context "get first location description" do
    test "nil description when no first location" do
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:raw_secret_in_git_history?).returns(true)
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:first_location).returns(nil)
      issues = @payload_builder.send(:get_issues_for_alerts, [get_empty_token])
      result = @payload_builder.send(:get_first_location_description, get_empty_token, issues)

      assert_nil result
    end

    test "nil description when unknown location type" do
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:raw_secret_in_git_history?).returns(true)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_type).returns(:SOME_UNKNOWN_TYPE)
      issues = @payload_builder.send(:get_issues_for_alerts, [get_empty_token])
      result = @payload_builder.send(:get_first_location_description, get_empty_token, issues)

      assert_nil result
    end

    test "describes as 'no longer present' when first location not in history" do
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:raw_secret_in_git_history?).returns(false)
      issues = @payload_builder.send(:get_issues_for_alerts, [get_empty_token])
      result = @payload_builder.send(:get_first_location_description, get_empty_token, issues)

      assert_equal "Secret is no longer present in git history", result
    end

    test "describes as 'secret' when first location not a custom pattern" do
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:raw_secret_in_git_history?).returns(true)
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:is_custom?).returns(false)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_type).returns(:REPOSITORY_BLOB)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:path).returns("/test/path")
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:start_line).returns(101)
      issues = @payload_builder.send(:get_issues_for_alerts, [get_empty_token])
      result = @payload_builder.send(:get_first_location_description, get_empty_token, issues)

      assert result.include?("Detected secret")
    end

    test "describes as 'custom pattern' when first location is a custom pattern" do
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:raw_secret_in_git_history?).returns(true)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_type).returns(:REPOSITORY_BLOB)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:path).returns("/test/path")
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:is_custom?).returns(true)
      issues = @payload_builder.send(:get_issues_for_alerts, [get_empty_token])
      result = @payload_builder.send(:get_first_location_description, get_empty_token, issues)

      assert result.include?("Detected custom pattern")
    end

    test "includes path when first location is a repo blob found in archive" do
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:raw_secret_in_git_history?).returns(true)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_type).returns(:REPOSITORY_BLOB)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:path).returns("/test/path")
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:found_in_archive?).returns(true)
      issues = @payload_builder.send(:get_issues_for_alerts, [get_empty_token])
      result = @payload_builder.send(:get_first_location_description, get_empty_token, issues)

      assert result.include?("/test/path")
    end

    test "includes path and line number when first location is a repo blob" do
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:raw_secret_in_git_history?).returns(true)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_type).returns(:REPOSITORY_BLOB)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:path).returns("/test/path")
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:start_line).returns(101)
      issues = @payload_builder.send(:get_issues_for_alerts, [get_empty_token])
      result = @payload_builder.send(:get_first_location_description, get_empty_token, issues)

      assert result.include?("/test/path:101")
    end

    test "includes path and line number when first location is a wiki blob" do
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:raw_secret_in_git_history?).returns(true)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_type).returns(:WIKI_BLOB)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:path).returns("/test/path")
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:start_line).returns(101)
      issues = @payload_builder.send(:get_issues_for_alerts, [get_empty_token])
      result = @payload_builder.send(:get_first_location_description, get_empty_token, issues)

      assert result.include?("Detected secret in GitHub wiki page /test/path:101")
    end

    test "includes issue number when first location is an issue" do
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:raw_secret_in_git_history?).returns(true)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_type).returns(:ISSUE_BODY)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_number).returns(@issue.number)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_id).returns(@issue.id)
      issues = @payload_builder.send(:get_issues_for_alerts, [get_empty_token])
      result = @payload_builder.send(:get_first_location_description, get_empty_token, issues)

      assert result.include?("issue ##{@issue.number}")
    end

    test "includes pull request number when first location is an issue location that is actually a pull request" do
      GitHub::TokenScanning::Service::Token.any_instance.stubs(:raw_secret_in_git_history?).returns(true)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_type).returns(:ISSUE_BODY)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_number).returns(@pull_request.number)
      GitHub::TokenScanning::Service::TokenLocation.any_instance.stubs(:content_id).returns(@pull_issue.id)
      issues = @payload_builder.send(:get_issues_for_alerts, [get_empty_token])
      result = @payload_builder.send(:get_first_location_description, get_empty_token, issues)

      assert result.include?("pull request ##{@pull_request.number}")
    end
  end

  def get_empty_token
    token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
      first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new,
    )
    GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
  end

  context "filters applied" do
    test "returns false when default is open query" do
      assert_equal false, @payload_builder.send(:filters_applied?, "is:open")
    end

    test "returns false when default is open query with sorting" do
      assert_equal false, @payload_builder.send(:filters_applied?, "is:open sort:updated-desc")
    end

    test "returns true when is closed query" do
      assert_equal true, @payload_builder.send(:filters_applied?, "is:closed")
    end

    test "returns true when is open query with other filters" do
      assert_equal true, @payload_builder.send(:filters_applied?, "is:open provider:adafruit")
    end
  end

  context "show results category" do
    test "shows results category when LowerConfidencePatterns is available" do
      SecretScanning::Features::Repo::LowerConfidencePatterns.any_instance.stubs(:feature_available?).returns(true)
      assert_equal true, @payload_builder.send(:show_results_category?)
    end

    test "shows results category when GenericSecrets is available" do
      SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:feature_available?).returns(true)
      assert_equal true, @payload_builder.send(:show_results_category?)
    end

    test "does not show results category when GenericSecrets and LowerConfidencePatterns are both unavailable" do
      SecretScanning::Features::Repo::GenericSecrets.any_instance.stubs(:feature_available?).returns(true)
      assert_equal true, @payload_builder.send(:show_results_category?)
    end
  end

  context "sort options" do
    test "sort options when query string has other qualifiers" do
      sort_options = @payload_builder.send(:generate_sort_options, "is:open sort:updated-desc provider:adafruit")

      expected_options = [
        {
          label: "Newest",
          slug: "created-desc",
          query: "is:open provider:adafruit sort:created-desc",
          checked: false,
          excluded: false,
        },
        {
          label: "Oldest",
          slug: "created-asc",
          query: "is:open provider:adafruit sort:created-asc",
          checked: false,
          excluded: false,
        },
        {
          label: "Recently updated",
          slug: "updated-desc",
          query: "is:open provider:adafruit sort:updated-desc",
          checked: true,
          excluded: false,
        },
        {
          label: "Least recently updated",
          slug: "updated-asc",
          query: "is:open provider:adafruit sort:updated-asc",
          checked: false,
          excluded: false,
        }
      ]
      assert_equal expected_options, sort_options
    end
  end

  context "resolution options" do
    test "resolution options when query is closed" do
      resolution_options = @payload_builder.send(:generate_resolution_options, @repo, "is:closed provider:adafruit")

      expected_options = [
        {
          label: "Revoked",
          slug: "revoked",
          query: "is:closed provider:adafruit resolution:revoked",
          checked: false,
          excluded: false,
        },
        {
          label: "False positive",
          slug: "false-positive",
          query: "is:closed provider:adafruit resolution:false-positive",
          checked: false,
          excluded: false,
        },
        {
          label: "Used in tests",
          slug: "used-in-tests",
          query: "is:closed provider:adafruit resolution:used-in-tests",
          checked: false,
          excluded: false,
        },
        {
          label: "Won't fix",
          slug: "wont-fix",
          query: "is:closed provider:adafruit resolution:wont-fix",
          checked: false,
          excluded: false,
        },
        {
          label: "Custom pattern edited",
          slug: "pattern-edited",
          query: "is:closed provider:adafruit resolution:pattern-edited",
          checked: false,
          excluded: false,
        },
        {
          label: "Custom pattern deleted",
          slug: "pattern-deleted",
          query: "is:closed provider:adafruit resolution:pattern-deleted",
          checked: false,
          excluded: false,
        },
        {
          label: "Ignored by configuration",
          slug: "hidden-by-config",
          query: "is:closed provider:adafruit resolution:hidden-by-config",
          checked: false,
          excluded: false,
        },
      ]
      assert_equal expected_options, resolution_options
    end

    test "resolution options when query custom patterns is not available" do
      SecretScanning::Features::Repo::CustomPatterns.any_instance.stubs(:feature_available?).returns(false)

      resolution_options = @payload_builder.send(:generate_resolution_options, @repo, "is:closed provider:adafruit")

      expected_options = [
        {
          label: "Revoked",
          slug: "revoked",
          query: "is:closed provider:adafruit resolution:revoked",
          checked: false,
          excluded: false,
        },
        {
          label: "False positive",
          slug: "false-positive",
          query: "is:closed provider:adafruit resolution:false-positive",
          checked: false,
          excluded: false,
        },
        {
          label: "Used in tests",
          slug: "used-in-tests",
          query: "is:closed provider:adafruit resolution:used-in-tests",
          checked: false,
          excluded: false,
        },
        {
          label: "Won't fix",
          slug: "wont-fix",
          query: "is:closed provider:adafruit resolution:wont-fix",
          checked: false,
          excluded: false,
        },
        {
          label: "Ignored by configuration",
          slug: "hidden-by-config",
          query: "is:closed provider:adafruit resolution:hidden-by-config",
          checked: false,
          excluded: false,
        },
      ]
      assert_equal expected_options, resolution_options
    end

    test "resolution options when resolution minused" do
      SecretScanning::Features::Repo::CustomPatterns.any_instance.stubs(:feature_available?).returns(false)

      resolution_options = @payload_builder.send(:generate_resolution_options, @repo, "is:closed provider:adafruit -resolution:revoked")

      expected_options = [
        {
          label: "Revoked",
          slug: "revoked",
          query: "is:closed provider:adafruit",
          checked: false,
          excluded: true,
        },
        {
          label: "False positive",
          slug: "false-positive",
          query: "is:closed provider:adafruit -resolution:revoked resolution:false-positive",
          checked: false,
          excluded: false,
        },
        {
          label: "Used in tests",
          slug: "used-in-tests",
          query: "is:closed provider:adafruit -resolution:revoked resolution:used-in-tests",
          checked: false,
          excluded: false,
        },
        {
          label: "Won't fix",
          slug: "wont-fix",
          query: "is:closed provider:adafruit -resolution:revoked resolution:wont-fix",
          checked: false,
          excluded: false,
        },
        {
          label: "Ignored by configuration",
          slug: "hidden-by-config",
          query: "is:closed provider:adafruit -resolution:revoked resolution:hidden-by-config",
          checked: false,
          excluded: false,
        },
      ]
      assert_equal expected_options, resolution_options
    end

    test "resolution options when multiple resolutions selected" do
      resolution_options = @payload_builder.send(:generate_resolution_options, @repo, "is:closed provider:adafruit resolution:revoked,used-in-tests")

      expected_options = [
        {
          label: "Revoked",
          slug: "revoked",
          query: "is:closed provider:adafruit resolution:used-in-tests",
          checked: true,
          excluded: false,
        },
        {
          label: "False positive",
          slug: "false-positive",
          query: "is:closed provider:adafruit resolution:revoked,used-in-tests,false-positive",
          checked: false,
          excluded: false,
        },
        {
          label: "Used in tests",
          slug: "used-in-tests",
          query: "is:closed provider:adafruit resolution:revoked",
          checked: true,
          excluded: false,
        },
        {
          label: "Won't fix",
          slug: "wont-fix",
          query: "is:closed provider:adafruit resolution:revoked,used-in-tests,wont-fix",
          checked: false,
          excluded: false,
        },
        {
          label: "Custom pattern edited",
          slug: "pattern-edited",
          query: "is:closed provider:adafruit resolution:revoked,used-in-tests,pattern-edited",
          checked: false,
          excluded: false,
        },
        {
          label: "Custom pattern deleted",
          slug: "pattern-deleted",
          query: "is:closed provider:adafruit resolution:revoked,used-in-tests,pattern-deleted",
          checked: false,
          excluded: false,
        },
        {
          label: "Ignored by configuration",
          slug: "hidden-by-config",
          query: "is:closed provider:adafruit resolution:revoked,used-in-tests,hidden-by-config",
          checked: false,
          excluded: false,
        },
      ]
      assert_equal expected_options, resolution_options
    end

    test "resolution clear all when multiple resolutions selected" do
      resolution_clear_all = @payload_builder.send(:resolution_clear_all, "is:closed provider:adafruit resolution:revoked,used-in-tests")

      expected = {
        label: "Clear closure reasons",
        slug: nil,
        query: "is:closed provider:adafruit",
        checked: false,
        excluded: false,
        hidden: false,
      }
      assert_equal expected, resolution_clear_all
    end
  end

  context "validity options" do
    test "validity options when none selected" do
      validity_options = @payload_builder.send(:generate_validity_options, @repo, "is:open")

      expected_options = [
        {
          label: "Active",
          slug: "active",
          query: "is:open validity:active",
          checked: false,
        },
        {
          label: "Inactive",
          slug: "inactive",
          query: "is:open validity:inactive",
          checked: false,
        },
        {
          label: "Unknown",
          slug: "unknown",
          query: "is:open validity:unknown",
          checked: false,
        },
      ]
      assert_equal expected_options, validity_options
    end

    test "validity options when one selected" do
      validity_options = @payload_builder.send(:generate_validity_options, @repo, "is:open validity:active")

      expected_options = [
        {
          label: "Active",
          slug: "active",
          query: "is:open",
          checked: true,
        },
        {
          label: "Inactive",
          slug: "inactive",
          query: "is:open validity:active,inactive",
          checked: false,
        },
        {
          label: "Unknown",
          slug: "unknown",
          query: "is:open validity:active,unknown",
          checked: false,
        },
      ]
      assert_equal expected_options, validity_options
    end

    test "validity options when multiple selected" do
      validity_options = @payload_builder.send(:generate_validity_options, @repo, "is:open validity:active,unknown")

      expected_options = [
        {
          label: "Active",
          slug: "active",
          query: "is:open validity:unknown",
          checked: true,
        },
        {
          label: "Inactive",
          slug: "inactive",
          query: "is:open validity:active,unknown,inactive",
          checked: false,
        },
        {
          label: "Unknown",
          slug: "unknown",
          query: "is:open validity:active",
          checked: true,
        },
      ]
      assert_equal expected_options, validity_options
    end

    test "validity clear all when multiple validities selected" do
      validity_clear_all = @payload_builder.send(:validity_clear_all, "is:open validity:active,unknown")

      expected = {
        label: "Clear validity",
        slug: nil,
        query: "is:open",
        checked: false,
        excluded: false,
        hidden: false,
      }
      assert_equal expected, validity_clear_all
    end
  end

  context "bypassed options" do
    test "bypassed options when none selected" do
      bypassed_options = @payload_builder.send(:generate_bypassed_options, @repo, "is:open")

      expected_options = [
        {
          label: "True",
          slug: "true",
          query: "is:open bypassed:true",
          checked: false,
        },
      ]
      assert_equal expected_options, bypassed_options
    end

    test "bypassed options when one selected" do
      bypassed_options = @payload_builder.send(:generate_bypassed_options, @repo, "is:open bypassed:true")

      expected_options = [
        {
          label: "True",
          slug: "true",
          query: "is:open",
          checked: true,
        },
      ]
      assert_equal expected_options, bypassed_options
    end

    test "bypassed clear all when bypassed is selected" do
      bypassed_clear_all = @payload_builder.send(:bypassed_clear_all, "is:open bypassed:true")

      expected = {
        label: "Clear bypassed",
        slug: nil,
        query: "is:open",
        checked: false,
        excluded: false,
        hidden: false,
      }
      assert_equal expected, bypassed_clear_all
    end
  end

  context "results category options" do
    test "results category options when query is closed" do
      results_category_options = @payload_builder.send(:generate_results_category_options, @repo, "is:closed provider:adafruit")

      expected_options = [
        {
          label: "Default",
          slug: Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS,
          query: "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS}",
          checked: true,
          excluded: false,
          count: nil,
        },
        {
          label: "Experimental",
          slug: Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS,
          query: "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS}",
          checked: false,
          excluded: false,
          count: 0,
        },
      ]
      assert_equal expected_options, results_category_options
    end

    test "results category options when results category minused" do
      resolution_options = @payload_builder.send(:generate_results_category_options, @repo, "is:closed provider:adafruit -#{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS}")

      expected_options = [
        {
          label: "Default",
          slug: Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS,
          query: "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS}",
          checked: true,
          excluded: true,
          count: nil,
        },
        {
          label: "Experimental",
          slug: Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS,
          query: "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS}",
          checked: false,
          excluded: false,
          count: 0,
        },
      ]
      assert_equal expected_options, resolution_options
    end

    test "results category options when default explicitly selected" do
      results_category_options = @payload_builder.send(:generate_results_category_options, @repo, "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS}")

      expected_options = [
        {
          label: "Default",
          slug: Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS,
          query: "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS}",
          checked: true,
          excluded: false,
          count: nil,
        },
        {
          label: "Experimental",
          slug: Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS,
          query: "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS}",
          checked: false,
          excluded: false,
          count: 0,
        },
      ]
      assert_equal expected_options, results_category_options
    end

    test "results category options when experimental selected" do
      results_category_options = @payload_builder.send(:generate_results_category_options, @repo, "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS}")

      expected_options = [
        {
          label: "Default",
          slug: Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS,
          query: "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS}",
          checked: false,
          excluded: false,
          count: nil,
        },
        {
          label: "Experimental",
          slug: Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS,
          query: "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS}",
          checked: true,
          excluded: false,
          count: 0,
        },
      ]
      assert_equal expected_options, results_category_options
    end

    test "results category options when multiselected" do
      results_category_options = @payload_builder.send(:generate_results_category_options, @repo, "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS},#{Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS}")

      expected_options = [
        {
          label: "Default",
          slug: Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS,
          query: "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::DEFAULT_RESULTS}",
          checked: true,
          excluded: false,
          count: nil,
        },
        {
          label: "Experimental",
          slug: Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS,
          query: "is:closed provider:adafruit #{Search::Queries::SecurityCenter::SecretScanningQuery::QUALIFIER_RESULTS_CATEGORY}:#{Search::Queries::SecurityCenter::SecretScanningQuery::EXPERIMENTAL_RESULTS}",
          checked: true,
          excluded: false,
          count: 0,
        },
      ]
      assert_equal expected_options, results_category_options
    end
  end
end
