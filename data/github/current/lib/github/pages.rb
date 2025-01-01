# typed: true
# frozen_string_literal: true
require "rack"
module GitHub
  module Pages
    autoload :Allocator, "github/pages/allocator"
    autoload :Builder, "github/pages/builder"
    autoload :BuildStatusObject, "github/pages/build_status_object"
    autoload :Creator, "github/pages/creator"
    autoload :DomainHealthChecker, "github/pages/domain_health_checker"
    autoload :DnsResolver, "github/pages/dns_resolver"
    autoload :EnterpriseBuilderApiClient, "github/pages/enterprise_builder_api_client"
    autoload :GarbageCollector, "github/pages/garbage_collector"
    autoload :Management, "github/pages/management"
    autoload :PagesDeployerClient, "github/pages/pages_deployer_client"
    autoload :ReplicationStrategy, "github/pages/replication_strategy"
    autoload :Replicator, "github/pages/replicator"
    # Repository page (gh-pages branch) automatic creator.
    #
    # See also: Repository#pages_create
    #
    # Returns nothing.
    def self.create(repo, user, params)
      Creator.new(repo, user, params).run
    end
  end
end
