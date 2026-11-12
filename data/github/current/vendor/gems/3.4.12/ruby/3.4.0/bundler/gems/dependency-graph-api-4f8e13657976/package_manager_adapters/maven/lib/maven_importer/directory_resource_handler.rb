require "fileutils"

module Maven
  class DirectoryResourceHandler
    # Implements the interface WritableResourceHandler
    include org.apache.maven.index.reader.WritableResourceHandler
    include Logging

    attr_reader :root_path

    def initialize(root_path)
      @root_path = Pathname.new(root_path)
      FileUtils.mkdir_p(@root_path)
      @resouces = []
    end

    def close
      @resouces.each do |f|
        f.close
      end
    end

    def locate(name)
      path = @root_path.join(name)
      logger.info("File request for #{path}")
      FileResource::ReadWriteFile.new(path).tap do |r|
        @resouces << r
      end
    end

  end
end
