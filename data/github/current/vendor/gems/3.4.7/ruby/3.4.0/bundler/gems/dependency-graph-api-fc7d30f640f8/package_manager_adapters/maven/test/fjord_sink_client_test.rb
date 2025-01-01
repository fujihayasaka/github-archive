require "test_helper"
require "socket"
require "cgi"

class FjordSinkClientTest < Minitest::Test
  def setup
    @sink_server = FjordSinkServer.new
    @sink_server.start
    @sink = Maven::FjordSinkClient.new(@sink_server.url, @sink_server.url, flush_interval: 5)
  end

  def teardown
    @sink_server.close
  end

  def test_flush_every_interval
    12.times do |i|
      @sink << FakePackageRelease.new({ package_manager: :maven, package_name: "foo_#{i}" })
    end

    assert_equal 10, @sink_server.package_releases.count
    @sink.flush
    assert_equal 12, @sink_server.package_releases.count
  end

  def test_checkpoint
    checkpoint = @sink.checkpoint("central")
    checkpoint.set(42)
    assert_equal 42, checkpoint.value

    checkpoint.set(1)
    assert_equal 1, checkpoint.value

    bar = @sink.checkpoint("bar")
    assert_equal 0, bar.value
  end
end
