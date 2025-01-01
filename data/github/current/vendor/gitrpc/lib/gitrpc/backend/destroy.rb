# frozen_string_literal: true

module GitRPC
  class Backend
    NETWORK_STORAGE_PATH_PATTERN = %r{/(?:dgit\d{1,2}/)?[0-9a-f]/nw/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{2}/\d+$}

    rpc_writer :destroy_network_replica, no_git_repo: true
    def destroy_network_replica(nwpath)
      # The user-supplied path must look like a valid network storage path, and
      # also match the rpc object.
      raise IllegalPath, nwpath unless nwpath =~ NETWORK_STORAGE_PATH_PATTERN
      raise IllegalPath, nwpath unless nwpath == path

      # The rm command can fail if a new file is created in the repository
      # after it has finished deleting files/subdirs but before deleting the
      # top level directory.  Instances of `dgit-state` being created have been
      # observed, due to a race between jobs.  To protect against this, let's
      # allow the deletion to be retried once.
      res = nil
      2.times do
        res = spawn(["rm", "-rf", nwpath])
        break if res["ok"]
      end

      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      nil
    end
  end
end
