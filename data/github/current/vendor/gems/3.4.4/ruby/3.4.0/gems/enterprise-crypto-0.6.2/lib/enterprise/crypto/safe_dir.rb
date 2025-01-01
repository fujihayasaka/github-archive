require 'pathname'
require 'securerandom'
require 'tmpdir'

module Enterprise
  module Crypto
    module SafeDir
      def tmpdir
        @tmpdir ||= begin
          # gpg-agent fails due to temp dir path lengths on darwin.
          # to work around, use a shorter path under /tmp
          dir = ::Dir.mktmpdir(nil, '/tmp')
          Kernel.at_exit { FileUtils.rm_rf dir }
          Pathname(dir)
        end
      end

      def mktmpdir(name = nil)
        hex = SecureRandom.hex(6)
        dir = tmpdir.join(name ? "#{name}.#{hex}" : hex)
        dir.mkpath
        dir
      end
    end
  end
end
