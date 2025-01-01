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
            "gel7acprodeus1file0.blob.core.windows.net",
            "si05acprodeus1file1.blob.core.windows.net",
            "aw97acprodeus1file2.blob.core.windows.net",
            "mp1yacprodeus1file3.blob.core.windows.net",
            "n06iacprodeus1file4.blob.core.windows.net",
            "ki6cacprodeus1file5.blob.core.windows.net",
            "95s5acprodeus1file6.blob.core.windows.net",
            "gk2hacprodeus1file7.blob.core.windows.net",
            "vth0acprodeus2file0.blob.core.windows.net",
            "frsnacprodeus2file1.blob.core.windows.net",
            "4qfyacprodeus2file2.blob.core.windows.net",
            "kv4gacprodeus2file3.blob.core.windows.net",
            "1k4dacprodeus2file4.blob.core.windows.net",
            "sd5kacprodeus2file5.blob.core.windows.net",
            "y2oiacprodeus2file6.blob.core.windows.net",
            "prtcacprodeus2file7.blob.core.windows.net",
          ] + GitHub.actions_scale_unit_domains,
          # wild card list of domains to allow for Actions functionality, self-hosted or vnet injected
          # used for greater stability and less frequent update monitoring
          "wildcard_domains" =>
          [
            "*.githubusercontent.com",
            "*.core.windows.net",
            "*.github.com",
            "github.com",
            "ghcr.io",
          ],
        }
      end
    end
  end
end

require "github/config/actions_scale_unit_domains"
