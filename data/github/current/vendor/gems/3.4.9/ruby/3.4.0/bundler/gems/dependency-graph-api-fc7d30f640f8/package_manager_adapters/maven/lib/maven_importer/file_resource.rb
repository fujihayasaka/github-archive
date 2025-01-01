module Maven
  module FileResource
    class ReadonlyFile
      # Implements the interface Resouce
      include DirectoryResourceHandler::Resource

      def initialize(path)
        @path = path
        @file = nil
      end

      def close
        @file.close if @file
      end

      def read
        file.to_inputstream if exists?
      end

      def exists?
        File.exist?(@path)
      end

      protected
      def file
        @file ||= File.open(@path, "r")
      end
    end

    class ReadWriteFile < ReadonlyFile
      # Implements the interface WritableResouce
      include DirectoryResourceHandler::WritableResource

      def write
        file_w.to_outputstream
      end

      def close
        super
        @file_w.close if @file_w
      end

      protected
      def file_w
        @file_w ||= File.open(@path, "w")
      end
    end
  end
end
