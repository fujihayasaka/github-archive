require "test_helper"
require "fileutils"

class IntegrationTest < Minitest::Test

  def setup
    @remote = FixturesResourceHandler.new
    @local = Maven::DirectoryResourceHandler.new("maven_data/")

    @sink_server = FjordSinkServer.new
    @sink_server.start
    @sink = Maven::FjordSinkClient.new(@sink_server.url, @sink_server.url)
  end

  def teardown
    @sink_server.close
    @remote.close
    # make sure we clean the local folder to not leak out
    FileUtils.rm_rf("maven_data/")
    @local.close
  end

  def test_full_import
    importer = Maven::Importer.new(@sink_server.url,
                                   @sink_server.url,
                                   local_file_handler: @local,
                                   remote_file_handler: @remote)

    assert_equal ["nexus-maven-repository-index.gz"], importer.index_reader.getChunkNames.to_a

    # Wont call import here as we don't want to import the full index in tests.
  end

  def test_incremental_import
    # set the last checkpoint
    @sink.checkpoint("central").set(524)

    importer = Maven::Importer.new(@sink_server.url,
                                   @sink_server.url,
                                   local_file_handler: @local,
                                   remote_file_handler: @remote)
    assert_equal ["nexus-maven-repository-index.525.gz"], importer.index_reader.getChunkNames.to_a

    importer.import

    assert_equal 6859, @sink_server.package_releases.count
    assert_equal({ "package_manager"=>"maven", "package_name"=>"xin.xihc:spring-jba", "package_version"=>"1.1.9", "published_at"=>1533588954 }.to_json, @sink_server.package_releases.first["value"])
    assert_equal 525, @sink.checkpoint("central").value
  end

  def test_refuse_rollback
    # set the last checkpoint to a future value
    @sink.checkpoint("central").set(526)

    importer = Maven::Importer.new(@sink_server.url,
                                   @sink_server.url,
                                   local_file_handler: @local,
                                   remote_file_handler: @remote)
    assert_equal [], importer.index_reader.getChunkNames.to_a

    importer.import
    assert_equal 0, @sink_server.package_releases.count
  end

  def test_nothing_to_import
    # set the last checkpoint
    @sink.checkpoint("central").set(525)

    importer = Maven::Importer.new(@sink_server.url,
                                   @sink_server.url,
                                   local_file_handler: @local,
                                   remote_file_handler: @remote)
    assert_equal [], importer.index_reader.getChunkNames.to_a

    importer.import
    assert_equal 0, @sink_server.package_releases.count
  end
end
