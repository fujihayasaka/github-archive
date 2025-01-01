# typed: true
# frozen_string_literal: true

# GitRPC configuration. This brings in the library and configures some global
# values like the cache
#
# See https://github.com/github/gitrpc for project information.
require "github"
require "github/config/memcache"
require "bertrpc"

# Configure gitrpc to use the existing memcache connection
require "gitrpc"
GitRPC.cache = GitHub.cache
GitRPC.connect_timeout = 1.5
GitRPC.timeout = GitHub.gitrpc_timeout
GitRPC.hooks_template = "#{GitHub.repository_template}/hooks"

# Configure the local host name (defaults to `localhost`)
GitRPC.local_git_host_name = GitHub.local_git_host_name

# Enable skipping the network for GitRPC on GHES
GitRPC.optimize_local_access = GitHub.enterprise?

# Make sure the instrumentation is configured
GitRPC.instrumenter = ActiveSupport::Notifications

# Set the max request size to 40 MiB
GitRPC.max_request_size = 40 * 1024 * 1024

class BERTRPC::Service
  def host
    GitHub::DNS.auto_fqdn(@host)
  end
end
