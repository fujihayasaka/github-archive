require "open-uri"
require "tmpdir"
require "fileutils"

require_relative "./directory_resource_handler"
require_relative "../logging.rb"

module Maven
  class HttpResourceHandler
    # Implements the interface ResourceHandler
    include org.apache.maven.index.reader.ResourceHandler
    include Logging

    def initialize(root_url)
      @root_url = URI(root_url)
      # Save the remote files locally, so we can stream them,
      # and don't need to hold them in-memory, however,
      # that needs to be in a tmp folder, so we will not re-use them
      # as the remote sources could change.
      @tmpdir = Dir.mktmpdir("maven-index")
      @local_cache = DirectoryResourceHandler.new(@tmpdir)
    end

    def close
      @local_cache.close
      FileUtils.rm_rf(@tmpdir)
    end

    def locate(name)
      url = @root_url + name
      logger.info("HTTP request for #{url}")
      local_copy = @local_cache.locate(name)
      if local_copy.exists?
        logger.info("Cache hit for #{url}")
        local_copy
      else
        logger.info("Cache miss for #{url}. Downloading file.")
        local_io = local_copy.write.to_io
        remote_io = URI.open(url, "User-Agent" => "GitHub Maven Dependency Indexer")
        IO.copy_stream(remote_io, local_io)
        local_io.close

        @local_cache.locate(name)
      end
    end
  end
end
