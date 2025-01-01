require "test_helper"

class GitHubTrilogyAdapter::QueryRetriesTest < TestCase
  test "#execute answers results for valid, retried, query" do
    mock_connection = Minitest::Mock.new Trilogy.new(@configuration)

    # Cause an ER_SERVER_SHUTDOWN error (code 1053) after the session is
    # set. On retry, the adapter will get a real, working connection.
    server_shutdown_error = Trilogy::ProtocolError.new
    server_shutdown_error.instance_variable_set(:@error_code, 1053)
    mock_connection.expect(:query, Trilogy::Result.new) { raise server_shutdown_error }

    adapter = trilogy_adapter(query_retries: 1)
    adapter.instance_variable_set(:@raw_connection, mock_connection)

    result = adapter.execute "SELECT * FROM posts;"

    assert_equal %w[id author_id title body kind created_at updated_at], result.fields
    assert mock_connection.verify
    mock_connection.close
  end
end
