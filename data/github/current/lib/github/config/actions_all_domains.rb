# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ActionsInbound
      def self.meta_info
        {
          "full_domains" => [
            # core domains
            "github.com",
            "api.github.com",
            "codeload.github.com",
            "objects.githubusercontent.com",
            "objects-origin.githubusercontent.com",
            "github-releases.githubusercontent.com",
            "github-registry-files.githubusercontent.com",
            "vstoken.actions.githubusercontent.com",
            "broker.actions.githubusercontent.com",
            "launch.actions.githubusercontent.com",
            "runner-auth.actions.githubusercontent.com",
            "release-assets.githubusercontent.com",
            # run service
            "run-actions-1-azure-eastus.actions.githubusercontent.com",
            "run-actions-2-azure-eastus.actions.githubusercontent.com",
            "run-actions-3-azure-eastus.actions.githubusercontent.com",
            # provjobd's "hidden" domain
            "setup-tools.actions.githubusercontent.com",
            # packages
            "ghcr.io",
            "npm.pkg.github.com",
            "npm-proxy.pkg.github.com",
            "npm-beta-proxy.pkg.github.com",
            "npm-beta.pkg.github.com",
            "nuget.pkg.github.com",
            "rubygems.pkg.github.com",
            "maven.pkg.github.com",
            "docker.pkg.github.com",
            "docker-proxy.pkg.github.com",
            "pypi.pkg.github.com",
            "containers.pkg.github.com",
            "swift.pkg.github.com",
            "pkg.actions.githubusercontent.com",
            # results and artifacts
            "results-receiver.actions.githubusercontent.com",
            "productionresultssa0.blob.core.windows.net",
            "productionresultssa1.blob.core.windows.net",
            "productionresultssa2.blob.core.windows.net",
            "productionresultssa3.blob.core.windows.net",
            "productionresultssa4.blob.core.windows.net",
            "productionresultssa5.blob.core.windows.net",
            "productionresultssa6.blob.core.windows.net",
            "productionresultssa7.blob.core.windows.net",
            "productionresultssa8.blob.core.windows.net",
            "productionresultssa9.blob.core.windows.net",
            "productionresultssa10.blob.core.windows.net",
            "productionresultssa11.blob.core.windows.net",
            "productionresultssa12.blob.core.windows.net",
            "productionresultssa13.blob.core.windows.net",
            "productionresultssa14.blob.core.windows.net",
            "productionresultssa15.blob.core.windows.net",
            "productionresultssa16.blob.core.windows.net",
            "productionresultssa17.blob.core.windows.net",
            "productionresultssa18.blob.core.windows.net",
            "productionresultssa19.blob.core.windows.net",
            # hosted compute
            "hosted-compute-request-orchestrator-prod-iad-01.githubapp.com",
            "hosted-compute-request-orchestrator-prod-iad-02.githubapp.com",
            "hosted-compute-request-orchestrator-prod-eus-01.githubapp.com",
            "hosted-compute-request-orchestrator-prod-eus-02.githubapp.com",
          ] + GitHub.actions_scale_unit_domains,
          # wild card list of domains to allow for Actions functionality, self-hosted or vnet injected
          # used for greater stability and less frequent update monitoring
          "wildcard_domains" =>
          [
            "*.githubusercontent.com",
            "*.core.windows.net",
            "*.githubapp.com",
            "*.github.com",
            "github.com",
            "ghcr.io",
          ],
        }
      end

      # Proxima domains for actions_inbound.
      # Source: https://docs.github.com/en/enterprise-cloud@latest/admin/data-residency/network-details-for-ghecom
      STAMP_TO_STORAGE_PREFIX = T.let({
        "prod-sdc-01" => "prodsdc01",
        "prod-weu-01" => "prodweu01",
        "prod-ae-01" => "prodae01",
        "prod-jpw-01" => "prodjpw01",
        "prod-cus-01" => "prodcus01",
        "staff-wus2-01" => "staffwus201",
        "test-cnc-01" => "testcnc01",
        "prod-wus3-01" => "prodwus301",
        "test-krc-01" => "testkrc01",
      }.freeze, T::Hash[String, String])

      def self.proxima_results_storage_domains
        stamp = GitHub::Config::Proxima.current_stamp_or_dotcom
        prefix = STAMP_TO_STORAGE_PREFIX[stamp]
        return [] unless prefix

        (0..3).map { |i| "#{prefix}resultssa#{i}.blob.core.windows.net" }
      end

      def self.proxima_run_service_domains
        stamp = GitHub::Config::Proxima.current_stamp_or_dotcom
        return [] unless GitHub::Config::Proxima::ALL_STAMPS.include?(stamp)

        # Each stamp runs 3 Proxima instances across 3 availability zones
        # Except prod-weu-01 and staff-wus2-01 which run only 1 instance
        max_proxima_instance_num = %w[prod-weu-01 staff-wus2-01].include?(stamp) ? 1 : 3
        max_availability_zone_num = 3

        tenant = GitHub.host_name_with_tenant

        (1..max_proxima_instance_num).flat_map do |i|
          (1..max_availability_zone_num).map { |j| "run-proxima-#{i}-#{stamp}-az#{j}.actions.#{tenant}" }
        end
      end

      # best source so far is digging aronund in ro-keyset files here:
      # https://github.com/github/hosted-compute-gps/tree/main/data
      def self.proxima_request_orchestrator_domains
        stamp = GitHub::Config::Proxima.current_stamp_or_dotcom
        return [] unless GitHub::Config::Proxima::ALL_STAMPS.include?(stamp)

        # staff and prod-cus-01 just use the dotcom system
        if stamp == "staff-wus2-01" || stamp == "prod-cus-01"
          [
            "hosted-compute-request-orchestrator-prod-iad-01.githubapp.com",
            "hosted-compute-request-orchestrator-prod-iad-02.githubapp.com",
            "hosted-compute-request-orchestrator-prod-eus-01.githubapp.com",
            "hosted-compute-request-orchestrator-prod-eus-02.githubapp.com",
          ]
        else
          ["hosted-compute-request-orchestrator-#{stamp}.githubapp.com"]
        end
      end

      # Proxima domains for actions_inbound.
      # Extras taken from splunk query of working customer https://splunk-eu.githubapp.com/en-US/app/search/search?q=search%20index%3Dglb%20bbvatest%20%7C%20stats%20count%20by%20host_header&display.page.search.mode=smart&dispatch.sample_ratio=1&workload_pool=Standard&earliest=-3d%40d&latest=now&display.page.search.tab=statistics&display.general.type=statistics&sid=1758630066.12468_1307F4A6-ADA0-401A-B0F2-476AE0CD6B49
      def self.proxima_meta_info
        tenant = GitHub.host_name_with_tenant
        {
          "full_domains" => [
            # api and core
            tenant,
            "api.#{tenant}",
            # actions
            "actions.#{tenant}",
            "broker.actions.#{tenant}",
            "results-receiver.actions.#{tenant}",
            "launch-receiver.actions.#{tenant}",
            "setup-tools.actions.githubusercontent.com",
            "release-assets.githubusercontent.com",
            # packages
            "npm.#{tenant}",
            "nuget.#{tenant}",
            "rubygems.#{tenant}",
            "maven.#{tenant}",
            "containers.#{tenant}",
            "pypi.#{tenant}",
            "swift.#{tenant}",
            "pkg.actions.#{tenant}",
            # github
            "github.com",
            "codeload.#{tenant}",
            "objects-origin.#{tenant}",
            "github-raw.#{tenant}",
          ] + proxima_results_storage_domains + proxima_run_service_domains + proxima_request_orchestrator_domains + GitHub.actions_scale_unit_domains,
          "wildcard_domains" => [
            "#{tenant}",
            "*.#{tenant}",
            "github.com",
            "*.githubapp.com", # needed for hosted compute request orchestrator domains
            "*.githubusercontent.com",
            "*.core.windows.net",
          ],
        }
      end

      # Proxima domains for the domains.actions section.
      def self.proxima_actions_domains
        tenant = GitHub.host_name_with_tenant
        [
          "#{tenant}",
          "*.#{tenant}",
          "github.com",
          "setup-tools.actions.githubusercontent.com",
          "release-assets.githubusercontent.com",
        ] + proxima_results_storage_domains + proxima_request_orchestrator_domains + GitHub.actions_scale_unit_domains
      end
    end
  end
end

require "github/config/actions_scale_unit_domains"
