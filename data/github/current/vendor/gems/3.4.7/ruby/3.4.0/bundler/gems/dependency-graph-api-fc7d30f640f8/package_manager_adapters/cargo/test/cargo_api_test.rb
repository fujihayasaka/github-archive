require "fake_fjord_sink_server"
require_relative "vcr_setup"
require_relative "../lib/cargo_api"

class CargoApiTest < Minitest::Test
  def setup
    Scrolls.init(stream: StringIO.new)
    @fjord_sink_server = FakeFjordSinkServer.new
    @fjord_sink_server.start
    @fjord_sink = Cargo::FjordSink.new(fjord_url: @fjord_sink_server.url, checkpoints_url: @fjord_sink_server.url)
  end

  def teardown
    @fjord_sink_server.close
  end

  def test_single_package_all_versions_import
    VCR.use_cassette("crates_io") do
      importer = Cargo::Api.new(fjord_sink: @fjord_sink)
      importer.import_package_release(package_name: "dg-test-crate")

      assert_equal 2, @fjord_sink_server.package_releases.count

      release123 = next_release
      assert_equal "rust", release123["package_manager"]
      assert_equal "dg-test-crate", release123["package_name"]
      assert_equal "1.2.3", release123["package_version"]
      assert_equal 99, release123["download_count"]
      assert_equal "MIT OR Apache-2.0", release123["license"]
      assert_equal "https://github.com/github/dependency-graph-api", release123["source_url"]
      assert_equal "https://docs.rs/dg-test-crate", release123["docs_url"]
      assert_equal "https://dg.github.io/rust", release123["home_url"]

      deps123 = release123["dependencies"]
      assert_equal 3, deps123.count
      assert_equal "bincode", deps123.first["package_name"]
      assert_equal "runtime", deps123.first["scope"]
      assert_equal ">= 1.2.1, < 2.0.0", deps123.first["requirements"]

      release060 = next_release
      assert_equal "rust", release060["package_manager"]
      assert_equal "dg-test-crate", release060["package_name"]
      assert_equal "0.6.0", release060["package_version"]
      assert_equal 88, release060["download_count"]
      assert_equal "MIT OR Apache-2.0", release060["license"]
      assert_equal "https://github.com/github/dependency-graph-api", release060["source_url"]
      assert_equal "https://docs.rs/dg-test-crate", release060["docs_url"]
      assert_equal "https://dg.github.io/rust", release060["home_url"]

      deps060 = release060["dependencies"]
      assert_equal 3, deps060.count
      assert_equal "bincode", deps060.first["package_name"]
      assert_equal "runtime", deps060.first["scope"]
      assert_equal ">= 1.2.1, < 2.0.0", deps060.first["requirements"]
    end
  end

  def test_single_package_single_version_import
    VCR.use_cassette("crates_io") do
      importer = Cargo::Api.new(fjord_sink: @fjord_sink)
      importer.import_package_release(package_name: "dg-test-crate", target_version: "0.6.0")

      assert_equal @fjord_sink_server.package_releases.count, 1

      release060 = next_release
      assert_equal "rust", release060["package_manager"]
      assert_equal "dg-test-crate", release060["package_name"]
      assert_equal "0.6.0", release060["package_version"]
      assert_equal 88, release060["download_count"]
      assert_equal "MIT OR Apache-2.0", release060["license"]
      assert_equal "https://github.com/github/dependency-graph-api", release060["source_url"]
      assert_equal "https://docs.rs/dg-test-crate", release060["docs_url"]
      assert_equal "https://dg.github.io/rust", release060["home_url"]

      deps060 = release060["dependencies"]
      assert_equal 3, deps060.count
      assert_equal "bincode", deps060.first["package_name"]
      assert_equal "runtime", deps060.first["scope"]
      assert_equal ">= 1.2.1, < 2.0.0", deps060.first["requirements"]
    end
  end

  def test_latest_packages_update_with_older_checkpoint
    VCR.use_cassette("crates_io") do
      importer = Cargo::Api.new(fjord_sink: @fjord_sink)

      # only dg-test-crate versions 1.2.3 and 0.6.0 should have
      # been updated more recently than this checkpoint
      previous_checkpoint = DateTime.parse("2021-06-20T00:00:00.00000+00:00")
      importer.set_checkpoint(Cargo::CRATES_IO_CHECKPOINT, previous_checkpoint)

      importer.import_latest_releases

      assert_equal @fjord_sink_server.package_releases.count, 2

      release123 = next_release
      assert_equal "rust", release123["package_manager"]
      assert_equal "dg-test-crate", release123["package_name"]
      assert_equal "1.2.3", release123["package_version"]
      assert_equal 99, release123["download_count"]
      assert_equal "MIT OR Apache-2.0", release123["license"]
      assert_equal "https://github.com/github/dependency-graph-api", release123["source_url"]
      assert_equal "https://docs.rs/dg-test-crate", release123["docs_url"]
      assert_equal "https://dg.github.io/rust", release123["home_url"]

      deps123 = release123["dependencies"]
      assert_equal 3, deps123.count
      assert_equal "bincode", deps123.first["package_name"]
      assert_equal "runtime", deps123.first["scope"]
      assert_equal ">= 1.2.1, < 2.0.0", deps123.first["requirements"]

      release060 = next_release
      assert_equal "rust", release060["package_manager"]
      assert_equal "dg-test-crate", release060["package_name"]
      assert_equal "0.6.0", release060["package_version"]
      assert_equal "MIT OR Apache-2.0", release060["license"]
      assert_equal 88, release060["download_count"]
      assert_equal "https://github.com/github/dependency-graph-api", release060["source_url"]
      assert_equal "https://docs.rs/dg-test-crate", release060["docs_url"]
      assert_equal "https://dg.github.io/rust", release060["home_url"]

      deps060 = release060["dependencies"]
      assert_equal 3, deps060.count
      assert_equal "bincode", deps060.first["package_name"]
      assert_equal "runtime", deps060.first["scope"]
      assert_equal ">= 1.2.1, < 2.0.0", deps060.first["requirements"]
    end
  end

  def test_latest_packages_update_from_recent_checkpoint
    VCR.use_cassette("crates_io") do
      importer = Cargo::Api.new(fjord_sink: @fjord_sink)

      # only dg-test-crate version 1.2.3 should have been
      # updated more recently than this checkpoint
      previous_checkpoint = DateTime.parse("2022-06-20T00:00:00.00000+00:00")
      importer.set_checkpoint(Cargo::CRATES_IO_CHECKPOINT, previous_checkpoint)

      importer.import_latest_releases

      assert_equal @fjord_sink_server.package_releases.count, 1

      release123 = next_release
      assert_equal "rust", release123["package_manager"]
      assert_equal "dg-test-crate", release123["package_name"]
      assert_equal "1.2.3", release123["package_version"]
      assert_equal 99, release123["download_count"]
      assert_equal "MIT OR Apache-2.0", release123["license"]
      assert_equal "https://github.com/github/dependency-graph-api", release123["source_url"]
      assert_equal "https://docs.rs/dg-test-crate", release123["docs_url"]
      assert_equal "https://dg.github.io/rust", release123["home_url"]

      deps123 = release123["dependencies"]
      assert_equal 3, deps123.count
      assert_equal "bincode", deps123.first["package_name"]
      assert_equal "runtime", deps123.first["scope"]
      assert_equal ">= 1.2.1, < 2.0.0", deps123.first["requirements"]
    end
  end

  private

  def next_release
    JSON.parse(@fjord_sink_server.package_releases.shift["value"])
  end
end
