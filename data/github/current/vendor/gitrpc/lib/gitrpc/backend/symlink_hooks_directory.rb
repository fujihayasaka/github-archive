# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_writer :symlink_hooks_directory
    def symlink_hooks_directory(link_source: nil)
      link_source ||= GitRPC.hooks_template
      unless link_source && File.directory?(link_source)
        raise ArgumentError, "hooks directory #{link_source.inspect} does not exist"
      end
      link_dest   = "#{path}/hooks"

      FileUtils.rm_rf(link_dest)
      FileUtils.ln_s(link_source, link_dest)
      true
    end
  end
end
