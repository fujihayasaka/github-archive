# frozen_string_literal: true

module GitRPC
  class Backend
    class ContributionCaches
      module Disk

        protected

        # compresses and writes the data to disk at the specified PATH
        #
        # Returns nil.
        def store_data(content)
          compressed = Zlib::Deflate.deflate(content)
          write_file(compressed)
          nil
        end

        # Read the whole cache file in memory.
        #
        # Returns the raw content of the file as a String.
        def inflated_data
          Zlib::Inflate.inflate(backend.fs_read(path))
        end

        private

        # Atomically write and move the file
        def write_file(content)
          tmp_file_name = "#{path}.#{$$}.#{Time.now.to_f}"
          backend.fs_write(tmp_file_name, content)
          backend.fs_move(tmp_file_name, path)
        end
      end
    end
  end
end
