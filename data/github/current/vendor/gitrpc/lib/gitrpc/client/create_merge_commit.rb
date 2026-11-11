# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Create a merge commit
    #
    # base           - the commit to merge into
    # head           - the commit to merge
    # author         - author information hash
    # commit_message - the message to use for the commit
    def create_merge_commit(base, head, author, commit_message, options = {})
      author = stringify_keys(author)
      author_time = author["time"]
      author["time"] = author_time.iso8601

      args = [base, head, author, commit_message]
      if !options[:committer].nil?
        committer = stringify_keys(options.delete(:committer))
        committer["time"] = committer["time"].iso8601
        args << committer
      else
        args << nil
      end

      if block_given?
        base_data, err, details, tree_id, dogstats = send_message(:stage_signed_merge_commit, *args, **options)
        return [base_data, err, details, tree_id, dogstats] unless err.nil?
        signature = yield base_data, commit_time: author_time
        options[:tree] = tree_id

        if signature.nil? || signature.empty?
          result = send_message(:create_merge_commit, *args, **options)
        else
          result = send_message(:persist_signed_merge_commit, base_data, signature, *args, **options)
        end
        # unshift the dogstats from the previous call into the dogstats from the most recent call
        result[4] = dogstats + result[4] unless result[4].nil?
        result
      else
        send_message(:create_merge_commit, *args, **options)
      end
    end
  end
end
