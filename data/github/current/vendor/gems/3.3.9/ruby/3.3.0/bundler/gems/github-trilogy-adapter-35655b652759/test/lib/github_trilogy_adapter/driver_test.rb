require "test_helper"

class GitHubTrilogyAdapter::DriverTest < TestCase
  class FakeTrilogy < Trilogy
  end

  setup do
    ActiveRecord::ConnectionAdapters::TrilogyAdapter.database_driver = FakeTrilogy
  end

  teardown do
    ActiveRecord::ConnectionAdapters::TrilogyAdapter.database_driver = Trilogy
  end

  test "#database_driver= configures a custom driver" do
    adapter = ActiveRecord::ConnectionAdapters::TrilogyAdapter.new(@configuration)
    assert adapter.raw_connection.is_a?(FakeTrilogy)
  end

  test "parses ssl_mode as int" do
    adapter = trilogy_adapter(ssl_mode: 0)
    adapter.connect!

    assert adapter.active?
  end

  test "parses ssl_mode as string" do
    adapter = trilogy_adapter(ssl_mode: "disabled")
    adapter.connect!

    assert adapter.active?
  end

  test "parses ssl_mode as string prefixed" do
    adapter = trilogy_adapter(ssl_mode: "SSL_MODE_DISABLED")
    adapter.connect!

    assert adapter.active?
  end
end
