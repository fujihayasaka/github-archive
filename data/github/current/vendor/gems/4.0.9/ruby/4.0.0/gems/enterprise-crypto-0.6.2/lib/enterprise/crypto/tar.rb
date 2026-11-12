module Enterprise
  module Crypto
    module Tar
      include SafeDir

      def self.included(klass)
        klass.extend Ext
      end

      module Ext
        def from_tar(tar_path, output = mktmpdir.to_path)
          # reads a tar file in tar_path and extracts it to directory in output
          child_pid = Process.spawn("tar", "-C", output, "-xf", tar_path)
          _, status = Process.waitpid2(child_pid)
          status.success?
        rescue SystemCallError => e
          false
        end
      end

      def to_tar(input, output = secure_tmp_path)
        # cd into directory in input and create a tar file in output
        filenames = Dir.chdir(input) { Dir.glob("*") }
        child_pid = Process.spawn("tar", "-cf", output, *filenames, :chdir => input)
        Process.waitpid2(child_pid)
        File.open(output)
      end

      def secure_tmp_path
        File.join(mktmpdir, SecureRandom.hex)
      end
    end
  end
end
