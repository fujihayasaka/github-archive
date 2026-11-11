# typed: true
# frozen_string_literal: true

module Stafftools
  class LargeFileStorageView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include PlatformHelper
    include ActionView::Helpers::NumberHelper

    attr_reader :account, :lfs_networks, :lfs_disk_usage, :lfs_repos

    # A formatted JSON hash of repositories and the LFS storage used by them,
    # as well as download bandwidth used (if any), for sending to users.
    #
    # Returns a Hash.
    def lfs_repos_json
      hash = {}

      lfs_repos.each do |repo|
        # disk_usage = number_to_human_size(node.stafftools_info.network_lfs_disk_usage)
        disk_usage = number_to_human_size(lfs_disk_usage[repo.network_id])
        hash[repo.name_with_owner] = {
          storage: disk_usage,
        }

        bandwidth = bandwidth_for_repo(repo)
        unless bandwidth.nil?
          download_usage = number_to_human_size(bandwidth[:bandwidth_down] * (1024**3))
          hash[repo.name_with_owner][:bandwidth] = download_usage
        end
      end

      JSON.pretty_generate(hash)
    end

    def bandwidth_for_repo(repo)
      return nil if GitHub.enterprise?
      lfs_networks && lfs_networks[repo&.network&.id]
    end
  end
end
