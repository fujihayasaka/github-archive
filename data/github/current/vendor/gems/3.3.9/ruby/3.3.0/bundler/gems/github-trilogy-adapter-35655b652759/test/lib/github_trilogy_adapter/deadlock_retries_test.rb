require "test_helper"

class GitHubTrilogyAdapter::DeadlockRetriesTest < TestCase
  test "#execute fails with deadlock error when retries are exhausted" do
    adapter = trilogy_adapter
    deadlocking_adapter = trilogy_adapter(query_retries: 1)

    # Add seed data
    adapter.execute("TRUNCATE posts")
    adapter.insert("INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES('Setup', 'Example', 'Content', NOW(), NOW())")

    adapter.transaction do
      adapter.execute(
        "UPDATE posts SET title = 'Connection 1' WHERE title != 'Connection 1';"
      )

      # Decrease the lock wait timeout in this session
      deadlocking_adapter.execute("SET innodb_lock_wait_timeout = 1")

      # QUERY_DEADLOCK notification sent on deadlock retry
      assert_notification("sql_deadlock.active_record") do
        assert_raises(ActiveRecord::LockWaitTimeout) do
          deadlocking_adapter.execute(
            "UPDATE posts SET title = 'Connection 2' WHERE title != 'Connection 2';"
          )
        end
      end
    end
  end

  test "#execute answers result when deadlock errors are resolved on retries" do
    adapter = trilogy_adapter

    sql = "SELECT * FROM posts;"
    proof_result = adapter.execute sql

    mock_connection = Minitest::Mock.new Trilogy.new(@configuration)

    # Cause an ER_LOCK_DEADLOCK error (code 1213) after the session is set
    # and recover from the deadlock in the following query
    deadlock_error = Trilogy::ProtocolError.new
    deadlock_error.instance_variable_set(:@error_code, 1213)
    mock_connection.expect(:query, Trilogy::Result.new) { raise deadlock_error }
    mock_connection.expect :query, proof_result, [sql]

    adapter = trilogy_adapter(query_retries: 1)
    adapter.instance_variable_set(:@raw_connection, mock_connection)

    result = adapter.execute sql
    assert_equal proof_result, result
  end

  test "#execute cannot recover from a deadlock during a transaction" do
    result = Trilogy::Result.new
    result.instance_variable_set(:@rows, [])

    mock_connection = Minitest::Mock.new Trilogy.new(@configuration)
    mock_connection.expect :query, result, [/BEGIN/]

    # Cause an ER_LOCK_DEADLOCK error (code 1213) after the transaction is
    # started; this is not recoverable, so it will be re-raised despite query
    # retries being enabled
    deadlock_error = Trilogy::ProtocolError.new
    deadlock_error.instance_variable_set(:@error_code, 1213)
    mock_connection.expect(:query, result) { raise deadlock_error }

    # The transaction will be rolled back
    mock_connection.expect :query, result, [/ROLLBACK/]

    adapter = trilogy_adapter(query_retries: 1)
    adapter.instance_variable_set(:@raw_connection, mock_connection)

    assert_raises(ActiveRecord::Deadlocked) do
      adapter.transaction do
        adapter.execute "SELECT * FROM posts;"
      end
    end
  end

  test "#transaction emits a query deadlock notification if there's a deadlock error" do
    adapter = trilogy_adapter(query_retries: 1)
    deadlocking_adapter = trilogy_adapter

    # Add seed data
    adapter.execute("TRUNCATE posts")
    adapter.insert("INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES('Setup', 'Example', 'Content', NOW(), NOW())")

    assert_notification("sql_deadlock.active_record") do
      adapter.transaction do
        adapter.execute("UPDATE posts SET title = 'Connection 1' WHERE title != 'Connection 1';")

        deadlocking_adapter.transaction do
          # Decrease the lock wait timeout in this session
          deadlocking_adapter.execute("SET innodb_lock_wait_timeout = 1")

          deadlocking_adapter.execute("UPDATE posts SET title = 'Connection 2' WHERE title != 'Connection 2';")
        end
      end
    rescue ActiveRecord::LockWaitTimeout
      # The error is raised after retries are exhausted
    end
  end

  test "retries a transaction with the configured number of deadlock_retries" do
    adapter = trilogy_adapter(deadlock_retries: 2)
    deadlocking_adapter = trilogy_adapter

    attempt_count = 0

    # Seed data
    adapter.execute("TRUNCATE posts")
    adapter.insert("INSERT INTO posts (title, kind, body, created_at, updated_at) VALUES('Setup', 'Example', 'Content', NOW(), NOW())")

    deadlocking_adapter.transaction do
      deadlocking_adapter.execute("UPDATE posts SET title = 'Connection 1' WHERE title != 'Connection 1';")

      # The error is raised after retries are exhausted
      assert_raises(ActiveRecord::LockWaitTimeout) do
        # We have a deadlock between adapter and deadlocking_adapter
        adapter.transaction do
          attempt_count += 1
          # Decrease the lock wait timeout in this session
          adapter.execute("SET innodb_lock_wait_timeout = 1")

          adapter.execute("UPDATE posts SET title = 'Connection 2' WHERE title != 'Connection 2';")
        end
      end
    end

    # The first attempt raises the count from 0 to 1, and then we retry two more times going to 3.
    assert_equal 3, attempt_count
  end
end
