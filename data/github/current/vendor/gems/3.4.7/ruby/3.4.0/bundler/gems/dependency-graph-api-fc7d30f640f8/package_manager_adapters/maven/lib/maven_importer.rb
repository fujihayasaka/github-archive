require_relative "logging"

require "jar_dependencies"
Jars.require_jars_lock!

require_relative "maven_importer/http_resource_handler"
require_relative "maven_importer/directory_resource_handler"
require_relative "maven_importer/package_release"
require_relative "maven_importer/checkpoint_index_reader"
require_relative "maven_importer/fjord_sink_client"
require_relative "maven_importer/file_resource"

module Maven
  import org.apache.maven.index.reader.Record

  FJORD_URL = ENV.fetch("FJORD_URL", "http://localhost:8085") # production value comes from Vault
  CHECKPOINTS_URL = ENV.fetch("API_URL", "http://localhost:9596")

  def self.run_importer
    remote = HttpResourceHandler.new("https://repo1.maven.org/maven2/.index/")
    local = DirectoryResourceHandler.new("/src/app/package_manager_adapters/maven/data/maven/local-cache")

    importer = Importer.new(FJORD_URL, CHECKPOINTS_URL, local_file_handler: local, remote_file_handler: remote)
    importer.import
  ensure
    remote.close if remote
    local.close if local
  end

  class Importer
    include Logging

    attr_reader :index_reader

    def initialize(sink_address, checkpoint_address, local_file_handler: nil, remote_file_handler: nil, index_reader: nil)
      @sink_address = sink_address
      @sink_client = Maven::FjordSinkClient.new(sink_address, checkpoint_address)
      @index_reader = index_reader || CheckpointIndexReader.new(@sink_client, local_file_handler, remote_file_handler)
      @record_expander = org.apache.maven.index.reader.RecordExpander.new
      @total_imported = 0
    end

    def import
      logger.info "Reading indexes: #{@index_reader.getChunkNames}"

      @index_reader.each do |chunk|
        # TODO: new thread?
        chunk.each do |record|
          record = @record_expander.apply(record)
          if record.getType == Record::Type::ARTIFACT_ADD
            @total_imported += 1
            @sink_client << PackageRelease.new(record, sink_address: @sink_address)
          end
        end

        @sink_client.flush
      end
      # reader close will write into the local cache the current processed
      # position of the index.
      # This needs to happen only if the chunk was successfuly procesed
      @index_reader.close

      logger.info "Done, imported #{@total_imported} packages"
    end
  end
end
