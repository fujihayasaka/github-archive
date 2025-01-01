# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesStafftoolsQueryTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @org     = create(:organization)
  end

  def assert_actions(exp, response)
    actions = response.results.collect { |h| h["action"] }.sort
    assert_same_elements exp, actions
  end

  test "orders results by timestamp" do
    with_es_refresh do
      es_log action: "team.create", org_id: @org.id, data: { team: "first" }
      es_log action: "team.create", org_id: @org.id, data: { team: "last" }
    end

    query = "org_id: #{@org.id}"

    # Default ordering is DESC
    response = Search::Queries::StafftoolsQuery.new(phrase: query, index_name: @audit_log_test_helper_index.name).execute
    assert_equal 2, response.total
    assert_equal "last", response.results.first["data"]["team"]

    response = Search::Queries::StafftoolsQuery.new(phrase: query, direction: "ASC", index_name: @audit_log_test_helper_index.name).execute
    assert_equal 2, response.total
    assert_equal "first", response.results.first["data"]["team"]
  end

  test "can search specific audit log index" do
    index_name = "audit_log-test0-d41d8cd98f00b204e9800998ecf8427e"
    query = Search::Queries::StafftoolsQuery.new(index_name: index_name)

    assert_equal index_name, query.query_params[:index]
  end

  context "when building query" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @query = Search::Queries::StafftoolsQuery.new
    end

    test "can build raw query" do
      phrase = "(user:dewski OR org:dewski) AND (action:user.delete OR action:org.delete)"
      expected = {
        bool: {
          must: { match_all: {} },
          filter: {
            query_string: {
              query: phrase,
              fields: Search::Queries::StafftoolsQuery::SEARCHABLE_FIELDS,
              default_operator: "AND",
            },
          },
        },
      }
      @query.phrase = phrase

      assert_equal expected, @query.build_query
    end
  end

  context "when executing the query" do
    test "can search for an email address without a qualifier" do
      with_es_refresh do
        log action: "team.add_member", data: { email: "bob-audit@example.com" }
        log action: "team.remove_member", data: { email: "jan-audit@example.com" }
      end

      response = Search::Queries::StafftoolsQuery.new(phrase: "bob-audit@example.com", index_name: @audit_log_test_helper_index.name).execute

      assert_equal 1, response.total
      assert_actions ["team.add_member"], response
    end

    test "can search for an email address with a qualifier" do
      with_es_refresh do
        log action: "team.add_member", data: { email: "steve@example.com" }
        log action: "team.add_member", data: { email: "jennifer@example.com" }
        log action: "team.remove_member", data: { email: "jennifer@example.com" }
      end

      response = Search::Queries::StafftoolsQuery.new(
        phrase: "jennifer@example.com action:team.remove_member",
        index_name: @audit_log_test_helper_index.name,
        type: "audit_entry",
      ).execute

      assert_equal 1, response.total
      assert_actions ["team.remove_member"], response
    end

    test "can search for a username without a qualifier" do
      with_es_refresh do
        log action: "team.add_member", user: "hat-trick"
        log action: "team.remove_member", user: "touchdown"
      end

      response = Search::Queries::StafftoolsQuery.new(
        phrase: "hat-trick",
        index_name: @audit_log_test_helper_index.name,
      ).execute

      assert_equal 1, response.total
      assert_actions ["team.add_member"], response
    end

    test "can search for an IP address without a qualifier" do
      with_es_refresh do
        log action: "team.add_member", actor_ip: "192.168.1.1"
        log action: "team.remove_member", actor_ip: "192.168.1.2"
      end

      response = Search::Queries::StafftoolsQuery.new(
        phrase: "192.168.1.2",
        index_name: @audit_log_test_helper_index.name,
      ).execute

      assert_equal 1, response.total
      assert_actions ["team.remove_member"], response
    end
  end

  context "query string length" do
    test "short queries work" do
      with_es_refresh do
        log action: "user.create", user: "joebob"
      end

      query_string = "user:joebob AND action:user.create"
      response = Search::Queries::StafftoolsQuery.new(
        phrase: query_string,
        index_name: @audit_log_test_helper_index.name,
      ).execute

      assert_equal 1, response.total
      assert_actions ["user.create"], response
    end

    test "long queries work" do
      with_es_refresh do
        log action: "user.create", user: "joebob"
      end

      actions = %w(
        user.create
        user.delete
        user.rename
        repo.create
        repo.delete
        repo.rename
        org.create
        team.create
      )
      query_string = "user:joebob AND (action:(#{actions.join(" OR ")}))"
      response = Search::Queries::StafftoolsQuery.new(
        phrase: query_string,
        index_name: @audit_log_test_helper_index.name,
      ).execute


      assert_equal 1, response.total
      assert_actions ["user.create"], response
    end
  end
end
