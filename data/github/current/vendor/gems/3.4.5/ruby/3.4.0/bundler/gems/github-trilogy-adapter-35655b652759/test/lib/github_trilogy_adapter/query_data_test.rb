require "test_helper"

class GitHubTrilogyAdapter::QueryDataTest < TestCase
  test "query flag for casting all decimals to big decimals is set" do
    assert (@adapter.instance_variable_get(:@raw_connection).query_flags & Trilogy::QUERY_FLAGS_CAST_ALL_DECIMALS_TO_BIGDECIMALS) != 0
  end

  test "#last_insert_id is accessible" do
    assert_equal 0, @adapter.last_insert_id

    @adapter.execute "INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('test', 'example', 'content', NOW(), NOW());"
    assert_equal 1, @adapter.last_insert_id
  end

  test "#last_gtid is tracked when enabled" do
    adapter = trilogy_adapter(track_gtid: true)

    if adapter.select_value("SELECT @@GLOBAL.log_bin") == 0
      return skip("bin_log needs to be enabled for GTID support")
    end

    assert_nil adapter.last_gtid

    adapter.execute "INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('test', 'example', 'content', NOW(), NOW());"
    assert_not_nil adapter.last_gtid

    # Running a read query should keep the last GTID
    adapter.execute "SELECT * FROM posts;"
    assert_not_nil adapter.last_gtid
  end

  # regression test for a bug fixed in
  # https://github.com/github/trilogy-adapter/pull/310 where query subscribers
  # observed a stale GTID in "COMMIT" payloads
  test "#last_gtid for query is available and fresh in query subscriber" do
    insert_query = "INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES ('test', 'example', 'content', NOW(), NOW());"
    adapter = trilogy_adapter(track_gtid: true).tap(&:verify!)

    if adapter.select_value("SELECT @@GLOBAL.log_bin") == 0
      return skip("bin_log needs to be enabled for GTID support")
    end

    subbed_gtids = {}
    cb = ->(*, payload) { subbed_gtids[payload[:sql]] = payload[:connection].last_gtid }

    ActiveSupport::Notifications.subscribed(cb, "sql.active_record") do
      adapter.begin_db_transaction
      adapter.execute(insert_query)
      adapter.commit_db_transaction
    end

    assert_equal ["BEGIN", insert_query, "COMMIT"], subbed_gtids.keys
    assert_nil subbed_gtids["BEGIN"]
    assert_nil subbed_gtids[insert_query]
    refute_nil subbed_gtids["COMMIT"], "expected GTID in COMMIT payload"
    refute_nil adapter.raw_connection.last_gtid, "expected adapter to have a GTID"
    assert_equal subbed_gtids["COMMIT"], adapter.raw_connection.last_gtid
  end
end
