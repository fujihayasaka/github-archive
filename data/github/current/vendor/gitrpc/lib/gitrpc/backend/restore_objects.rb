# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_writer :restore_objects, output_varies: true
    def restore_objects(max: nil)
      argv = ["-r", "--fast"]
      argv << "--max=#{max}" if max
      spawn_git("restore-objects", argv)
    end
  end
end
