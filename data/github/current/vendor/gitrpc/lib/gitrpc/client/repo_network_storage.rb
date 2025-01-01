# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    # Report disk space consumed by a repo network (in KB).  If there are
    # multiple backends and they disagree, conservatively return the
    # maximum amount.
    def nw_usage
      if backend.disagreement_possible?
        send_demux(:nw_usage).values.max
      else
        send_message(:nw_usage)
      end
    end

    def repo_disk_usage(ignore_refs = [])
      if backend.disagreement_possible?
        send_demux(:repo_disk_usage, ignore_refs).values.max
      else
        send_message(:repo_disk_usage, ignore_refs)
      end
    end

    # Report available disk space (in KB) on the partition holding the
    # repo network.  If there are multiple backends and they disagree,
    # conservatively return the minimum amount.
    def free_space
      if backend.disagreement_possible?
        send_demux(:free_space).values.min
      else
        send_message(:free_space)
      end
    end

    # Report the total size of all pack files in need of `nw-repack` (in
    # MB), as a possible trigger for network maintenance.  If there are
    # multiple backends and they disagree, conservatively return the
    # maximum amount.
    def get_unpacked_size
      if backend.disagreement_possible?
        send_demux(:get_unpacked_size).values.max
      else
        send_message(:get_unpacked_size)
      end
    end

    # Report the estimated size that would be required to run network
    # maintenance, in MB.  If there are multiple backends and they
    # disagree, conservatively return the maximum amount.
    def get_maint_size
      if backend.disagreement_possible?
        send_demux(:get_maint_size).values.max
      else
        send_message(:get_maint_size)
      end
    end
  end
end
