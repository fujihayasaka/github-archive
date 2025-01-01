# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Fetch the number of commits reachable from the passed in starting oid
    # filtered by additional options
    #
    # starting_oid (required) - the commit to start counting from
    # until_date (optional) - the date to count up until
    # since (optional) - the date to count from
    # path (optional) - count only commits that touch a specified path
    # author (optional) - count only commits authored by particular person
    # committer (optional) - count only commits committed by a particular person
    #
    # Returns the number of commits or nil
    def filterable_commit_count(starting_oid:, until_date: nil, since: nil, path: nil, author_emails: [], committer_emails: [])
      ensure_valid_full_oid(starting_oid)

      cache_key_params = [starting_oid, path, since, until_date, author_emails.sort.join(","), committer_emails.sort.join(",")]
      cache_key = repository_cache_key("filterable_commit_count", *cache_key_params)
      cache_fetch(cache_key, backend_method: :filterable_commit_count) do
        send_message(:filterable_commit_count, starting_oid, until_date, since, path, author_emails, committer_emails: committer_emails)
      end
    end
  end
end
