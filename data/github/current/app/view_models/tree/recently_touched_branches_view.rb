# typed: true
# frozen_string_literal: true

class Tree
  class RecentlyTouchedBranchesView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    attr_reader :current_repository, :can_push

    def recent_branches
      return @recent_branches if @recent_branches

      @recent_branches = []

      if can_push
        current_repository.recently_touched_branches_for(current_user).each do |branch|
          @recent_branches << branch.merge(repo: current_repository)
        end
      end

      if user_fork
        bad_oid = current_repository.default_oid
        user_fork.recently_touched_branches_for(current_user, bad_oid).each do |branch|
          @recent_branches << branch.merge(repo: user_fork)
        end
      end

      if current_repository.merge_queue_enabled?
        @recent_branches = @recent_branches.reject { |b| b[:name].start_with?(MergeQueue::READ_ONLY_BRANCH_SHORT_PREFIX) }
      end

      @recent_branches = @recent_branches.sort_by { |b| b[:date] }.first(3)
    end

    def user_fork
      return @user_fork if defined?(@user_fork)

      @user_fork = GitHub.dogstats.time("recently_touched_branches_view", tags: ["action:user_fork"]) do
        repo = current_repository.find_fork_in_network_for_user(current_user)
        repo if repo != current_repository
      end
    end

    # Returns a list of web socket channels that pertain
    # to live updates of the recently touched branches partial.
    def web_socket_channels
      channels = []

      if can_push
        channels << GitHub::WebSocket::Channels.post_receive(current_repository, current_user)
      end

      if user_fork
        channels << GitHub::WebSocket::Channels.post_receive(user_fork, current_user)
      end

      recent_branches.each do |branch|
        channels << GitHub::WebSocket::Channels.branch(branch[:repo], branch[:name])
      end

      channels.join(" ")
    end
  end
end
