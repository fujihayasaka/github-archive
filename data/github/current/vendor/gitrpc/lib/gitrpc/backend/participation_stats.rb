# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

require "set"

module GitRPC
  class Backend
    WEEK_SECONDS = (7 * 24 * 60 * 60)

    rpc_reader :participation_stats
    def participation_stats(base_oid, user_emails, end_date, weeks)
      ensure_valid_commitish(base_oid)

      user_emails = Set.new(user_emails.map &:downcase)
      start_date = end_date.to_i - (weeks * WEEK_SECONDS)

      res = spawn_git("log", ["--since", start_date.to_s, "--format=%ae %at", base_oid])

      p_all = Array.new(weeks) { 0 }
      p_owner = Array.new(weeks) { 0 }

      if res["ok"]
        res["out"].each_line do |line|
          authored_email, authored_time = line.split(" ", 2)

          authored_email.strip!
          authored_email.downcase!

          offset = (authored_time.to_i - start_date).to_i
          index = offset / WEEK_SECONDS
          next if index < 0 || index >= weeks

          p_all[index] += 1
          p_owner[index] += 1 if user_emails.include?(authored_email)
        end
      end

      { "all" => p_all, "owner" => p_owner }
    end
  end
end
