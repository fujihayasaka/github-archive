# typed: true
# frozen_string_literal: true

# Print a warning and (optionally) raise if anyone uses the
# backtick method to execute code.  Using backticks can lead to
# insecure code, as it invokes a shell, so if user entered input
# ever makes its way into the call, you have a severe security hole.
#
# Error class for when backtick method is called
class InsecureCommandExecution < RuntimeError; end

# This overrides the backtick method to send a warning and optionally raise
# when called
#
# Alternatives:
#   * look for a standard library providing the same function,
#     for example Socket.gethostname instead of `hostname`
#   * IO.popen
class Object
  def `(arg)
    callstack = caller
    if github_allowed_backtick_caller?(callstack)
      return super
    end
    boom = InsecureCommandExecution.new("insecure command execution via ` method from #{callstack[0]}")
    boom.set_backtrace(callstack)
    Failbot.report(boom)
    raise boom if Rails.env.test?
    super
  end

  GITHUB_BACKTICK_ALLOWLIST = Regexp.union(
    %r{config/timers\..+\.rb},
    %r{config/unicorn\.rb},
    %r{lib/active_support/core_ext},
    %r{lib/github/connect/authentication\.rb},
    %r{lib/rack/process_utilization\.rb},
    %r{test/integration/.+},
    %r{test/fast/linting/.+},
    %r{test/test_helpers/.+},
    %r{vendor/.+gems/byebug.+/lib/.+},
    %r{vendor/.+gems/enterprise-crypto.+/lib/.+},
    %r{vendor/.+gems/pry.+/lib/.+},
    %r{vendor/.+gems/dogapi.+/lib/capistrano/datadog.rb},
    %r{vendor/.+gems/dogapi.+/lib/dogapi/common.rb},
    %r{vendor/.+gems/stripe.+/lib/.+},
    %r{minitest/+unit\.rb},
    %r{minitest/+assertions\.rb},
    %r{ruby-progressbar/calculators/length.rb},
    %r{lib/resqued/worker_metrics\.rb}
  )

  def github_allowed_backtick_caller?(callstack)
    callstack[0] =~ GITHUB_BACKTICK_ALLOWLIST
  end
end
