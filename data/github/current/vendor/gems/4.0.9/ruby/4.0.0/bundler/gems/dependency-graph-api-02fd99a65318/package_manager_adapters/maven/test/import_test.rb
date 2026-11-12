require "test_helper"

class FakeIndexReader
  include Enumerable
  def initialize(index)
    @index = index
  end

  def each(&block)
    @index.each(&block)
  end

  def getChunkNames # rubocop:disable Naming/MethodName
    ["fake index reader"]
  end

  def close
  end
end

class ImportTest < Minitest::Test
  def setup
    @sink_server = FjordSinkServer.new
    @sink_server.start
  end

  def teardown
    @sink_server.close
  end

  def test_index_import
    index_reader = FakeIndexReader.new(
      [
        [{ index: 1 }, { index: 2 }],
        [{ index: 3 }, { index: 4 }, { index: 5 }]
      ]
    )

    importer = Maven::Importer.new(@sink_server.url, @sink_server.url, index_reader: index_reader)
    importer.import
    assert_equal 5, @sink_server.package_releases.count
  end
end
