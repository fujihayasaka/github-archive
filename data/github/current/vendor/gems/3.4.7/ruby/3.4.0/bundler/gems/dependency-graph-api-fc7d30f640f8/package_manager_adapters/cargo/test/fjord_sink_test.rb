require "fake_fjord_sink_server"
require_relative "../lib/fjord_sink"

## Lovingly copied from Nuget

class FjordSinkTest < Minitest::Test

  def setup
    @sink_server = FakeFjordSinkServer.new
    @sink_server.start
    @sink = Cargo::FjordSink.new(fjord_url: @sink_server.url, checkpoints_url: @sink_server.url)

    @release = {
        package_manager: "cargo",
        package_name: "test-package",
        version: "1.0.0",
        description: "A test package",
        authors: "Fredrick Tam",
        home_url: "http://test-package.com",
        published_at: "",
        dependencies: [
          {
          package_name: "test-package2",
          requirements: "1.3.2",
          scope: "runtime",
          },
          {
          package_name: "test-package3",
          requirements: "1.3.5",
          scope: "development",
          }
        ]

      }
  end

  def test_appends_package_to_package_releases
    puts @sink.package_releases
    @sink << @release
    assert_equal @sink.package_releases.count, 1
  end

  def test_flush_to_sink_successful_if_package_release_correctly_formatted
    @sink << @release
    assert_equal @sink.flush_package_releases, true

    # make sure package_releases array is made empty after successful flush
    puts @sink.package_releases
    assert_equal @sink.package_releases.count, 0
  end

  def teardown
    @sink_server.close
  end
end
