# frozen_string_literal: true
# typed: true

module GitRPC
  class Backend
    rpc_reader :push_log
    def push_log(
      ref: nil, limit: 50, pagination: nil, squash: nil,
      before_oid: nil, after_oid: nil, newer_than: nil, older_than: nil,
      condensed: nil, sanitized: nil, no_sanitized: nil,
      no_cprmcs: nil, no_pr_heads: nil, iso_times: nil, chronological: nil
    )
      argv = []
      argv << "--ref=#{ref}" if ref
      argv << "--limit=#{limit}" if limit
      argv << "--pagination" if pagination
      argv << "--squash" if squash
      argv << "--before-oid=#{before_oid}" if before_oid
      argv << "--after-oid=#{after_oid}" if after_oid
      argv << "--newer-than=#{newer_than}" if newer_than
      argv << "--older-than=#{older_than}" if older_than
      argv << "--condensed" if condensed
      argv << "--sanitized" if sanitized
      argv << "--no-sanitized" if no_sanitized
      argv << "--no-cprmcs" if no_cprmcs
      argv << "--no-pr-heads" if no_pr_heads
      argv << "--iso-times" if iso_times
      argv << "--chronological" if chronological

      res = spawn_git("push-log", argv)
      raise GitRPC::CommandFailed.new(res) if !res["ok"]
      res["out"].split("\n")
    end
  end
end
