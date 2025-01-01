# typed: false
# frozen_string_literal: true

module GitHub
  module Config
    # Let's NOT extend this into GitHub::Config; there's no need to pollute
    # that global namespace with these methods.
    module ArtifactAttestations
      def self.meta_info
        {
          "trust_domain" => "#{GitHub::Config::Proxima.current_stamp}",
          "services" => meta_services_urls,
        }
      end

      def self.meta_info_with_key
        { "artifact_attestations" => meta_info }
      end

      def self.meta_services_urls
        if GitHub.multi_tenant_enterprise?
          [
            "*.actions.githubusercontent.com",
            "tuf-repo.github.com",
            "fulcio.#{GitHub.host_name_with_tenant}",
            "timestamp.#{GitHub.host_name_with_tenant}",
          ]
        else
          [
            "*.actions.githubusercontent.com",
            "tuf-repo.github.com",
            "fulcio.githubapp.com",
            "timestamp.githubapp.com",
          ]
        end
      end
    end
  end
end
