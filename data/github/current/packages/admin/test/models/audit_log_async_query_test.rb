# typed: true
# frozen_string_literal: true
require "test_helper"

class AuditLogAsyncQueryTest < GitHub::TestCase
  include AuditLogAsyncQueryHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @actor = create(:user)
  end

  test "can only create export for user" do
    @business = create(:business, owners: [@actor])

    assert_no_difference "AuditLogAsyncQuery.count" do
      assert_raises ::ActiveRecord::AssociationTypeMismatch do
        query = AuditLogAsyncQuery.create({
          actor: @business
        })

        refute query.valid?
      end
    end
  end

  test "can create query for user" do
    assert_difference "AuditLogAsyncQuery.count" do
      client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
      client.mock_start
      query = AuditLogAsyncQuery.create({
        actor: @actor,
        per_page: 50,
        after: "",
        before: ""
      })
      assert query.persisted?
      assert query.query_id?, "expected query id to be generated"
    end
  end

  test "cannot create async query when other queries are already running" do
    # Max of 3 ongoing exports are allowed

    client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
    client.mock_check_status(completed: false, times: 3)

    ids = []
    (1..3).each do |_i|
      client.mock_start(operation_id: SecureRandom.uuid.to_s)
      query = AuditLogAsyncQuery.create({
        actor: @actor,
        per_page: 50,
        after: "",
        before: ""
      })
      ids << query.operation_id
    end

    assert_no_difference "AuditLogAsyncQuery.count" do
      client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
      ids.each { |id| client.mock_check_status(operation_id: id, completed: false) }

      invalid_query = AuditLogAsyncQuery.new({
        actor: @actor,
        per_page: 50,
        after: "",
        before: ""
      })

      refute invalid_query.valid?
      assert_equal ["can't create another async query because the maximum limit of in-progress exports has been reached"], invalid_query.errors[:actor]
    end
  end

  test "raises an error when starting a query returns warnings" do
    client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
    client.mock_start(operation_id: SecureRandom.uuid.to_s, warnings: ["there was a problem"])

    assert_raises ::AuditLogAsyncQuery::AsyncQueryrror do
      AuditLogAsyncQuery.create({
        actor: @actor,
        per_page: 50,
        after: "",
        before: ""
      })
    end
  end

  test "raises an error when getting a query status returns warnings" do
    client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
    client.mock_start
    client.mock_check_status(warnings: ["there was a problem"])
    query = AuditLogAsyncQuery.create({
      actor: @actor,
      per_page: 50,
      after: "",
      before: ""
    })

    assert_raises ::AuditLogAsyncQuery::AsyncQueryrror do
      query.is_completed?
    end
  end

  test "raises an error when getting a query results returns warnings" do
    client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
    client.mock_start
    client.mock_check_status
    client.mock_fetch_results(warnings: ["there was a problem"])
    query = AuditLogAsyncQuery.create({
      actor: @actor,
      per_page: 50,
      after: "",
      before: ""
    })

    assert_raises ::AuditLogAsyncQuery::AsyncQueryrror do
      query.results(per_page: 50, after: "", before: "")
    end
  end

  test "generates instrumentation event" do
    events = subscribe "user.audit_log_async_query"

    client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
    client.mock_start

    query = AuditLogAsyncQuery.create({
      actor: @actor,
      per_page: 50,
      after: "",
      before: ""
    })

    expected_payload = {
      query_id: query.query_id,
      operation_id: query.operation_id,
      actor: @actor.login,
      actor_id: @actor.id,
      user: @actor.login,
      user_id: @actor.id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "is_completed? return true and updates completed flag when query is expired" do
    client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
    client.mock_start

    query = AuditLogAsyncQuery.create({
      actor: @actor,
      per_page: 50,
      after: "",
      before: ""
    })

    travel 1.hour + 1.minute

    assert query.is_completed?
    assert query.completed
  end

  test "is_completed? return false when query is ongoing" do
    client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
    client.mock_start

    query = AuditLogAsyncQuery.create({
      actor: @actor,
      per_page: 50,
      after: "",
      before: ""
    })

    client.mock_check_status(operation_id: query.operation_id, completed: false)

    refute query.is_completed?
    refute query.completed
  end

  test "is_completed? return true and update completed flag when query is successfully completed" do
    client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
    client.mock_start

    query = AuditLogAsyncQuery.create({
      actor: @actor,
      per_page: 50,
      after: "",
      before: ""
    })

    client.mock_check_status(operation_id: query.operation_id, completed: true)

    # Should be false before is_completed? updates it
    refute query.completed
    assert query.is_completed?
    assert query.completed
  end

  test "unique query id and operation id generated doesn't clash with other query request" do
    client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")

    client.mock_start(operation_id: SecureRandom.uuid.to_s)
    query1 = AuditLogAsyncQuery.create({
      actor: @actor,
      per_page: 50,
      after: "",
      before: ""
    })

    client.mock_start(operation_id: SecureRandom.uuid.to_s)
    client.mock_check_status(operation_id: query1.operation_id, completed: true)
    query2 = AuditLogAsyncQuery.create({
      actor: @actor,
      per_page: 50,
      after: "",
      before: ""
    })

    refute_equal query1.query_id, query2.query_id
    refute_equal query1.operation_id, query2.operation_id
  end

  test "returns query_id for parameter" do
    client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
    client.mock_start

    query = AuditLogAsyncQuery.create({
      actor: @actor,
      per_page: 50,
      after: "",
      before: ""
    })

    assert_equal query.to_param, query.query_id
  end

  test "fetch_results returns results when query is completed" do
    client = MockAsyncQueryClient.new(per_page: 50, after: "", before: "")
    client.mock_start

    query = AuditLogAsyncQuery.create({
      actor: @actor,
      per_page: 50,
      after: "",
      before: ""
    })
    client.mock_check_status(operation_id: query.operation_id)
    client.mock_fetch_results(query_id: query.query_id, results: ["result"])

    results = query.results(per_page: 50, after: "", before: "")
    assert_equal 1, results[:total_count]
    assert_equal 0, results[:took]
    assert_equal "", results[:after]
    assert_equal "", results[:before]
    assert_equal ["result"], results[:results]
    assert_equal [], results[:warnings]
  end
end
