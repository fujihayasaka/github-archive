# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    def create_revert_commit(revert, ours, author, committer, commit_message, mainline = nil)
      author = stringify_keys(author)
      author_time = author["time"]
      author["time"] = author["time"].iso8601

      committer = stringify_keys(committer)
      committer["time"] = committer["time"].iso8601

      args = [revert, ours, author, commit_message, mainline, committer]

      if block_given?
        base_data, err = send_message(:stage_signed_revert_commit, *args)
        return [base_data, err] unless err.nil?
        signature = yield base_data, commit_time: author_time

        if signature.nil? || signature.empty?
          send_message(:create_revert_commit_rugged, *args)
        else
          send_message(:persist_signed_revert_commit, base_data, signature, *args)
        end
      else
        send_message(:create_revert_commit_rugged, *args)
      end
    end

    def create_revert_commits_for_range(range_start_commit_oid, range_end_commit_oid, target_commit_oid, author, committer, timeout: nil)
      author = stringify_keys(author)
      author["time"] = author["time"].iso8601

      committer = stringify_keys(committer)
      committer["time"] = committer["time"].iso8601

      return [nil, "timeout"] if timeout && timeout <= 0

      begin
        send_message(:create_revert_commits_for_range, range_start_commit_oid, range_end_commit_oid, target_commit_oid, author, committer, timeout)
      rescue GitRPC::Backend::RevertTimeout
        [nil, "timeout"]
      rescue GitRPC::Protocol::DGit::ResponseError => e
        # Treat split timeouts--some nodes timed out, others succeeded--as
        # equivalent to a unanimous timeout, rather than propagating a
        # messy ResponseError.
        errors_from_voting_routes = e.errors.select { |route, _| route.voting? }
        split_timeout = errors_from_voting_routes.all? do |_, error|
          error.is_a?(GitRPC::Backend::RevertTimeout)
        end

        if split_timeout
          return [nil, "timeout"]
        else
          raise
        end
      end
    end
  end
end
