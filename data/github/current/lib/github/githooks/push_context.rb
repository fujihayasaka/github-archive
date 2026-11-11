# typed: true
# frozen_string_literal: true

require "github"
require "github/config"
require "github/config/failbot"
require "github/githooks/hook_context"
require "faraday"
require "time"
require "cgi"

class GitHub::PushContext < GitHub::HookContext
  class HTTPStatusNotOkError < StandardError; end
  # 1 and 127 are already used to signal abnormal failures (eg. unhandled
  # exceptions, ruby process boot failure, etc.), so we use 2 as the exit code
  # for legitimate push rejections.
  FAILURE_CODE = 2
  MAX_RETRIES = 3

  class InvalidRefsError < StandardError; end
  attr_reader :pushed_refs
  attr_reader :input
  attr_reader :committed_at
  attr_reader :githooks_api_url_with_tenant

  def initialize(input)
    super()
    @input = input
    @pushed_refs = parse_refs(input)
    if @pushed_refs.empty?
      GitHub.dogstats.increment("git.hooks.pre_receive.errors", tags: ["type:emptyrefs"])
      exit FAILURE_CODE
    end
    @committed_at = sockstat_var(:committed_at) || ENV["GIT_COMMITTER_DATE"]
    @githooks_api_url_with_tenant = sockstat_var(:githooks_api_url_with_tenant)
  end

  def check(*checks)
    checks.each do |check|
      stats_name = check.name.sub("GitHub::PreReceive", "").downcase
      before = Time.now.to_f
      puts("starting #{check} hook...") if user_has_operator_mode?

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      warnings, errors = check.new(self).check
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      GitHub.dogstats.distribution("git.hooks.runtime", (end_time - start_time) * 1_000, tags: ["action:pre_receive", "type:#{stats_name}"])

      unless warnings.empty?
        GitHub.dogstats.increment("git.hooks.pre_receive.warnings", tags: ["type:#{stats_name}"])
        puts warnings.uniq.join("\n")
      end

      unless errors.empty?
        puts errors.uniq.join("\n")
        GitHub.dogstats.increment("git.hooks.pre_receive.errors", tags: ["type:#{stats_name}"])
        exit FAILURE_CODE
      end

      after = Time.now.to_f
      duration_in_s = after - before
      puts("finished #{check} hook in #{'%.3f' % duration_in_s}sec") if user_has_operator_mode?
    end
  end

  def quarantine_path
    ENV["GIT_QUARANTINE_PATH"]
  end

  def githooks_api_url
    return ENV["TEST_GITHOOKS_API_URL"] if use_env_githooks_api_url?
    return githooks_api_url_with_tenant if githooks_api_url_with_tenant.present?
    GitHub.githooks_api_url
  end

  def failbot_info
    info = super
    if GitHub.enterprise?
      info.update(
        refs: pushed_refs,
      )
    end
    info
  end

  def notify_app(path, hmac_key, pre_receive_args = {})
    refs = pushed_refs.map do |before_oid, after_oid, refname|
      {
        refname: CGI.escape(refname),
        before_oid: before_oid,
        after_oid: after_oid,
      }
    end

    timestamp = Time.now.to_i.to_s
    hmac_sign = OpenSSL::HMAC.hexdigest("sha256", hmac_key, timestamp)

    retry_count = 0
    connection = Faraday.new(url: "#{githooks_api_url}#{path}")

    begin
      req_body = {
        "protocol": proto,
        "ref_updates": refs,
      }
      req_body["pusher"] = CGI.escape(pusher) unless pusher.nil?
      req_body["committed_at"] = CGI.escape(committed_at) unless committed_at.nil?

      resp = connection.post do |req|
        req.headers["Content-Type"] = "application/json"
        req.headers["Request-HMAC"] = "#{timestamp}.#{hmac_sign}"
        req.body = req_body.merge(pre_receive_args).to_json
      end

      GitHub.dogstats.increment("git.hooks.post-receive.response_status", tags: ["code:#{resp.status}"])

      if resp.status != 202
        raise HTTPStatusNotOkError.new("Expected HTTP 202 for #{path} but got #{resp.status} with headers: #{resp.headers} and body: #{resp.body}.")
      end

      resp
    rescue Faraday::Error, HTTPStatusNotOkError => err
      if (retry_count += 1) <= MAX_RETRIES
        sleep(0.5)
        retry
      end
      Failbot.report(err)
      nil
    end
  end

  private

  SHA1_REGEX = /\A[0-9a-f]{40}\z/

  def use_env_githooks_api_url?
    Rails.env.test?
  end

  def parse_refs(input)
    rejected_lines = []
    refs = input.each_line.map do |line|
      before, after, ref = line.chomp.split(" ", 3)

      if before =~ SHA1_REGEX && after =~ SHA1_REGEX
        [before, after, ref]
      else
        rejected_lines << line
        nil
      end
    end.compact

    raise InvalidRefsError if refs.empty?
    refs
  rescue InvalidRefsError => e
    Failbot.report(e, input: input,
                      repo_id: repo_id,
                      rejected_lines: rejected_lines)
    []
  end
end
