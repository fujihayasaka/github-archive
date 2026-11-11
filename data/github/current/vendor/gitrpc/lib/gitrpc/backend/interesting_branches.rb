# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "set"

module GitRPC
  class Backend
    FOR_EACH_REF_MAX = 50

    rpc_reader :interesting_branches
    def interesting_branches(default_branch, limit)
      prs = find_pull_request_shas || Set.new

      # We need as many branches as possible (more than the given 'limit')
      # to give us more choices when choosing interesting vs uninteresting.
      # However, we don't want to parse an stupid amount of lines, so we
      # cut this at a default limit
      res = spawn_git("for-each-ref",
                      ["--count=#{FOR_EACH_REF_MAX}",
                       "--sort=-committerdate",
                       "--format=%(committerdate:raw) %(objectname) %(refname)",
                       "refs/heads"])

      return [] if !res["ok"]

      not_interesting = []
      interesting = []

      # Let's divide all the parsed branches into 'interesting'
      # (the ones that don't have any PRs open) and 'uninteresting'
      # (the ones that do)
      res["out"].each_line do |line|
        line = line.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace)
        timestamp, _, sha1, ref = line.rstrip.split(" ", 4)
        ref = ref.b.sub(%r{^refs/heads/}, "")
        next if ref == default_branch

        branch = [timestamp.to_i, sha1, ref]

        if prs.include?(sha1)
          not_interesting << branch
        else
          interesting << branch
          break if interesting.size == limit
        end
      end

      # Figure out if we have as many interesting branches
      # as we needed. If we don't, we'll backfill from the
      # uninteresting ones
      missing = limit - interesting.size
      if missing > 0
        interesting += not_interesting.take(missing)
        interesting.sort_by! { |time, _, _| time }
        interesting.reverse!
      end

      interesting.take(limit)
    end

    private
    def find_pull_request_shas
      res = spawn_git("for-each-ref", ["--format=%(objectname)", "refs/pull"])
      if res["ok"]
        Set.new(res["out"].each_line.map(&:rstrip))
      end
    end
  end
end
