require "test_helper"

class GitHubTrilogyAdapter::ConnectionInstrumentationTest < TestCase
  test "establishing a connection emits notification" do
    adapter = trilogy_adapter

    assert_notification("establish_connection.active_record") do
      adapter.execute("SELECT 1")
    end
  end

  test "can reconnect after failing to rollback" do
    adapter = trilogy_adapter(read_timeout: 1)

    adapter.transaction do
      adapter.execute("SELECT 1")

      # Cause the client to disconnect without the adapter's awareness
      assert_raises Trilogy::TimeoutError do
        adapter.instance_variable_get(:@raw_connection).query("SELECT sleep(2)")
      end

      raise ActiveRecord::Rollback
    end

    assert_notification("connect.active_record") do
      adapter.execute("SELECT 1")
    end
  end

  test "can reconnect after failing to commit" do
    adapter = trilogy_adapter(read_timeout: 1)

    assert_raises ActiveRecord::ConnectionFailed do
      adapter.transaction do
        adapter.execute("SELECT 1")

        # Cause the client to disconnect without the adapter's awareness
        assert_raises Trilogy::TimeoutError do
          adapter.instance_variable_get(:@raw_connection).query("SELECT sleep(2)")
        end
      end
    end

    assert_notification("connect.active_record") do
      adapter.execute("SELECT 1")
    end
  end


  test "#quote_string emits connect notification" do
    assert_notification("connect.active_record", host: @host, database: DATABASE) do
      adapter = trilogy_adapter
      adapter.quote_string "test"
    end
  end

  test "#quote_string emits exhausted connection retry notification for retriable exception" do
    result = Trilogy::Result.new
    result.instance_variable_set(:@rows, [])

    mock_connection = Minitest::Mock.new Trilogy.new(@configuration)
    mock_connection.expect(:query, nil) { raise Trilogy::EOFError }
    mock_connection.expect(:query, nil) { raise Trilogy::EOFError }

    Trilogy.stub :new, mock_connection do
      adapter = trilogy_adapter

      assert_notification("connection_retries_exhausted.active_record") do
        # Trilogy.new raises the exception after sending the notification.
        # (And the original Trilogy::EOFError gets wrapped by the adapter.)
        assert_raises(ActiveRecord::ConnectionFailed) do
          adapter.quote_string "test"
        end
      end
    end
  end

  test "#quote_string doesn't emit any notifications for non-retriable error" do
    mock_connection = Minitest::Mock.new Trilogy.new(@configuration)
    mock_connection.expect(:query, nil) { raise StandardError }

    Trilogy.stub :new, mock_connection do
      adapter = trilogy_adapter

      notifications = [
        "connection_retries_exhausted.active_record",
        "connection_unretriable.active_record",
        "retry_connection.active_record"
      ]

      assert_no_notification(/#{notifications.join("|")}/) do
        # The original error gets wrapped by the adapter
        assert_raises(ActiveRecord::StatementInvalid) do
          adapter.quote_string "test"
        end
      end
    end
  end

  test "#quote_string emits connection unretryable notification for an almost retriable exception" do
    mock_connection = Minitest::Mock.new Trilogy.new(@configuration)
    mock_connection.expect(:query, nil) { raise Trilogy::BaseError }

    Trilogy.stub :new, mock_connection do
      adapter = trilogy_adapter

      assert_notification("connection_unretriable.active_record", error_class_name: String) do
        # The original Trilogy::BaseError gets wrapped by the adapter
        assert_raises ActiveRecord::StatementInvalid do
          adapter.quote_string "test"
        end
      end
    end
  end

  test "#quote_string emits connection unretryable notification when connecting to unknown database" do
    adapter = trilogy_adapter(database: "does_not_exist")

    assert_notification("connection_unretriable.active_record", error_class_name: String) do
      # The Trilogy::ProtocolError raised by connecting to an unknown database is
      # translated to an ActiveRecord::NoDatabaseError
      assert_raises ActiveRecord::NoDatabaseError do
        adapter.execute "SELECT * FROM posts;"
      end
    end
  end

  test "#quote_string answers string when retrying lost connection errors" do
    # Raise a retryable exception on the first query attempt and recover on retry
    trilogy_new_method = Trilogy.method(:new)
    errored_once = false
    mock_new = Proc.new do |config|
      if errored_once
        trilogy_new_method.call(config)
      else
        errored_once = true
        raise Trilogy::EOFError.new
      end
    end

    Trilogy.stub :new, mock_new do
      adapter = trilogy_adapter

      result = nil

      # RETRY_CONNECTION notification sent on retry
      assert_notification("retry_connection.active_record") do
        result = adapter.quote_string "test"
      end

      assert_equal "test", result
    end
  end

  test "exec_query answers result when retrying lost connection errors" do
    adapter = trilogy_adapter(read_timeout: 1, query_retries: 1)

    # Make connection lost for future queries by exceeding the read timeout
    assert_raises(ActiveRecord::StatementInvalid) do
      adapter.execute "SELECT sleep(2);"
    end
    assert_not adapter.active?

    result = nil

    # RETRY_CONNECTION notification sent when reconnecting after lost
    # connection. The result will be set on the query retry.
    assert_notification("retry_connection.active_record") do
      result = adapter.exec_query "SELECT COUNT(*) FROM posts;"
    end

    assert_equal [[0]], result.rows
  end

  test "exec_query answers nil when lost connection errors" do
    adapter = trilogy_adapter(read_timeout: 1, query_retries: 0)

    adapter.execute "SELECT 1;"
    # Make connection lost for future queries
    adapter.raw_connection.close
    assert_not adapter.active?

    result = nil

    # No reconnect happens since the connection is verified
    assert_no_notification("retry_connection.active_record") do
      assert_raises(ActiveRecord::ConnectionFailed) do
        result = adapter.exec_query "SELECT 1;"
      end
    end
    assert_nil result
  end

  test "#execute does not retry within transaction" do
    adapter = trilogy_adapter(read_timeout: 1)

    assert_raises ActiveRecord::ConnectionFailed do
      adapter.transaction do
        # Make connection lost for future queries by exceeding the read timeout
        assert_raises(ActiveRecord::StatementInvalid) do
          adapter.execute "SELECT sleep(2);"
        end
        assert_not adapter.active?

        # RETRY_CONNECTION notification should not be sent, we should not be
        # reconnecting within a transaction
        assert_no_notification("retry_connection.active_record") do
          adapter.execute "SELECT COUNT(*) FROM posts;"
        end
      end
    end

    # connection should have been thrown away
    #assert_not adapter.instance_variable_get(:@verified)

    assert_notification("connect.active_record") do
      adapter.execute "SELECT COUNT(*) FROM posts;"
    end
  end

  test "execute answers result when retrying lost connection errors" do
    adapter = trilogy_adapter(read_timeout: 1, query_retries: 1)

    # Make connection lost for future queries by exceeding the read timeout
    assert_raises(ActiveRecord::StatementInvalid) do
      adapter.execute "SELECT sleep(2);"
    end
    assert_not adapter.active?

    result = nil

    # RETRY_CONNECTION notification sent when reconnecting after lost
    # connection. The result will be set on the query retry.
    assert_notification("retry_connection.active_record") do
      result = adapter.execute "SELECT COUNT(*) FROM posts;"
    end

    assert_equal [[0]], result.rows
  end
end
