# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Backend
    rpc_writer :dgit_state_init
    def dgit_state_init(checksum_version)
      ret = spawn_git("dgit-state", ["init", "--version=#{checksum_version}"])
      raise DGitStateInitError.new(ret["err"]) unless ret["ok"]

      dgit_state = fs_read("dgit-state")
      line = dgit_state.lines.first
      raise EmptyDGitState unless line
      line.chomp
    end

    def enumerate_backups(parent)
      Dir["#{parent}.backup.*"]
    end

    rpc_writer :prune_backups
    def prune_backups(parent, max_repair_backups)
      errors = {}
      backups = enumerate_backups(parent).sort
      if backups.size > max_repair_backups
        # Keep the oldest and max_repair_backups-1 of the newest; delete
        # any others.
        backups[1..-max_repair_backups].each do |backuppath|
          next if !backuppath.start_with?("#{parent}.backup")
          # FileUtils.rm_rf doesn't report errors in a useful way,
          # so use an external rm command.
          res = spawn(["rm", "-rf", backuppath])
          errors[backuppath] = res["err"] if !res["ok"]
        end
      end
      errors
    end
  end
end
