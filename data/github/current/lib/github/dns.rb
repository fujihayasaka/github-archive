# typed: true
# frozen_string_literal: true

# Expand hostnames to fqdn to work around dns lookup issues.
# Only applies to fileserver (github-fs, github-dfs) hosts, and never on
# Enterprise.
#
# To use it, replace...
#   foo(host)
# with...
#   foo(GitHub::DNS.auto_fqdn(host))
module GitHub
  class DNS
    def self.auto_fqdn(host)
      if !GitHub.enterprise? && host =~ /\Agithub-dfs\d+-cp1-prd\z/
        _deprecate_auto_fqdn(host)
        "#{host}.iad.github.net."
      elsif !GitHub.enterprise? && host =~ /\Agithub-dfs-[0-9a-f]+\z/
        _deprecate_auto_fqdn(host)
        host
      else
        host
      end
    end

    # Ideally, I'd use backscatter here. But it may not be all the
    # way set up, especially if this code path gets hit in one of
    # the lightweight scripts.
    #
    # I would also consider using dogstatsd, but if there is anything
    # that's still hitting this code path, I'd like to be able to
    # add more data to what's logged so that I can see where the calls
    # are coming from.
    #
    # So, this uses GitHub::Logger to capture information about the call.
    # AFAICT, GitHub::Logger is available anywhere that this code could
    # possibly run.
    def self._deprecate_auto_fqdn(host)
      GitHub::Logger.log(reason: "pr63738".freeze, fn: "auto_fqdn".freeze, host: host)

      # Occasionally log a little bit of the call stack.
      # This will help track down how it ends up getting called.
      if GitHub.respond_to?(:log_auto_fqdn_caller) && GitHub.log_auto_fqdn_caller
        # Don't log it again.
        GitHub.log_auto_fqdn_caller = false

        # Log a few of the interesting frames from the call stack.
        Failbot.report!(AutoFqdnDeprecation.new("deprecated use of GitHub::DNS.auto_fqdn"), app: "github-dgit-debug", backtrace: caller.join("\n"))
      end
    end

    class AutoFqdnDeprecation < StandardError
    end
  end
end
