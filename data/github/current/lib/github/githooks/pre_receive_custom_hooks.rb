# typed: true
# frozen_string_literal: true

require "github/ref_type"
require "shellwords"

class GitHub::PreReceiveCustomHooks
  SKIPPED_REF_TYPES = [:internal, :temp, :merge_queue].freeze

  def initialize(context)
    @context = context
  end

  def check
    warnings, errors = [], []

    refs = ""
    @context.pushed_refs.each do |before, after, ref|
      reftype = GitHub::RefType.detect_ref_type(ref)
      refs += "#{before} #{after} #{ref}\n" unless SKIPPED_REF_TYPES.include?(reftype)
    end

    # If there's nothing to check, don't run the hook script(s)
    return [warnings, errors] if refs.empty?

    max_timeout = (@context.config["git.hooktimeout"] || 5).to_i
    start = Time.now
    start_time = start.to_i

    if @context.pre_receive_hooks_overflow?
      errors << "Too many hooks configured for repository"
      return [warnings, errors]
    end

    begin
      @context.pre_receive_hooks.each do |hook|
        hook = GitHub::PreReceiveHookEntry.from_hash(hook)
        next if hook.enforcement == GitHub::PreReceiveHookEntry::DISABLED

        report_errors = false
        hook_error   = +""
        hook_warning = +""
        opts = { input: refs }
        if max_timeout != -1
          timeout = max_timeout - (Time.now.to_i - start_time)
          timeout = 1 if timeout < 1

          opts[:timeout] = timeout
        end

        begin
          child = Progeny::Command.new(custom_hooks_command(hook), opts)
          if child.status.exitstatus != 0
            if hook.enforcement == GitHub::PreReceiveHookEntry::ENABLED
              hook_error << "#{hook.script}: failed with exit status #{child.status.exitstatus}\n"
              hook_error << child.out.force_encoding("UTF-8").scrub
            else
              hook_warning << "#{hook.script}: failed with exit status #{child.status.exitstatus}\n"
              hook_warning << child.out.force_encoding("UTF-8").scrub
            end
            report_errors = true
          else
            hook_warning << child.out.force_encoding("UTF-8").scrub
          end
        rescue Progeny::TimeoutExceeded
          if hook.enforcement == GitHub::PreReceiveHookEntry::ENABLED
            hook_error << "#{hook.script}: execution exceeded #{max_timeout}s timeout\n"
          else
            hook_warning << "#{hook.script}: execution exceeded #{max_timeout}s timeout\n"
          end
          report_errors = true
          break
        ensure
          warnings << hook_warning unless hook_warning.empty?
          errors   << hook_error   unless hook_error.empty?
          if report_errors
            pre_receive_args = {
              "hook_warning": hook_warning,
              "hook_error": hook_error,
              "real_ip": @context.real_ip,
              "repo_path": @context.path,
            }

            key = GitHub.api_internal_pre_receive_hooks_hmac_keys.first.to_s
            path = URI("/internal/pre-receive-hooks/#{hook.hook_id}/errors")
            @context.notify_app(path, key, pre_receive_args)
          end
        end
      end
    ensure
      GitHub.stats.timing("git.hooks.pre_receive.custom.timing", ((Time.now - start) * 1000).round) if GitHub.enterprise?
      GitHub.dogstats.timing("git.hooks", ((Time.now - start) * 1000).round, tags: ["action:pre_receive", "type:custom"])
    end

    [warnings, errors]
  end

  def custom_hooks_command(hook)
    if Rails.env.production?
      repo_path = Dir.pwd
      env_path = "#{GitHub.custom_hooks_dir}/environments/#{hook.environment_id}/#{hook.checksum}"
      "/usr/local/share/enterprise/ghe-firejail #{env_path} #{repo_path} #{GitHub.custom_hooks_dir}/repos/#{hook.repository_id} #{Shellwords.shellescape(hook.script)} 2>&1"
    else
      "#{GitHub.custom_hooks_dir}/testenv/#{Shellwords.shellescape(hook.script)} 2>&1"
    end
  end
end
