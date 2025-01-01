# typed: true
# frozen_string_literal: true

module Networks
  class MembersView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    MAX_REPOS = 1000

    attr_reader :network

    def repo_map
      @repo_map ||= network_repos.group_by(&:parent_id)
    end

    def too_many_repos?
      return @too_many_repos if defined?(@too_many_repos)

      @too_many_repos = repositories_scope.count > MAX_REPOS
    end

    def no_forks?
      repo_map.size == 1 || repo_map[nil].blank?
    end

    # FIXME: we're not supposed to have any mixed-visibility networks, but
    # there are a few in production. Once those are figured out, we can probably
    # replace this with a version that doesn't even bother performing ability
    # checks on public networks.
    def network_repos
      public_repos, private_repos = repositories_scope.partition(&:public?)

      if private_repos.empty?
        public_repos << network.root unless public_repos.include?(network.root)
        return public_repos
      end

      private_repo_promises = private_repos.map do |repo|
        repo.async_readable_by?(current_user).then { |visible| repo if visible }
      end

      private_repos = Promise.all(private_repo_promises).sync.compact

      (public_repos + private_repos + [network.root]).uniq
    end

    def repositories_scope
      @repositories ||= begin
        # There are rare conditions that can cause a repo to not have an owner:
        # - The brief window between user deletion and execution of the job that deletes corresponding repos
        # - The longer window after an outage which caused repo deletion jobs not to run
        # To not HTTP 500 during those windows, we filter them out here.
        if GitHub.flipper[:exclude_cols_on_network_view].enabled?
          scope = network.repositories.select_except("description", "raw_data").with_owner.preload(owner: :profile)
        else
          scope = network.repositories.with_owner.preload(owner: :profile)
        end

        scope = scope.filter_spam_for(current_user)

        unless current_user
          scope = scope.public_scope
        end

        scope.limit(MAX_REPOS + 1)
      end
    end
  end
end
