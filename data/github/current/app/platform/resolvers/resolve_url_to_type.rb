# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ResolveUrlToType < Resolvers::Base
      type Unions::UrlResolvable, null: true

      argument :url, Scalars::URI, "The URL to resolve.", required: true

      def resolve(url:)
        unless Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to resolve urls.")
        end

        model = model_url_service.model_for_url(url)

        # For non-GitHub hosts, only accept Repository results (from Pages
        # custom domain resolution). Path-based matches like User or Team are
        # false positives for external URLs.
        if !github_or_associated_host?(url) && !model.is_a?(Repository)
          return nil
        end

        model
      rescue GitHub::Migrator::ModelForUrl::NotImplemented
        nil
      end

      private def github_or_associated_host?(url)
        host = Addressable::URI.parse(url)&.host.to_s.downcase
        return false if host.blank?

        # Configured GitHub host (covers GHES and local dev)
        return true if host_matches_domain?(host, GitHub.host_name)

        # Gist host
        gist_host = Addressable::URI.parse(GitHub.gist_url)&.host.to_s.downcase
        return true if gist_host.present? && host_matches_domain?(host, gist_host)

        # Pages host
        pages_host = GitHub.pages_host_name_v2.to_s.downcase
        return true if pages_host.present? && host_matches_domain?(host, pages_host)

        # Known GitHub-owned domains (e.g. github.com, github.io)
        all_github_domains = Page::CName::GITHUB_DOMAINS +
          GitHub::Migrator::ModelForUrl::ADDITIONAL_GITHUB_DOMAINS
        return true if all_github_domains.any? { |domain| host_matches_domain?(host, domain) }

        false
      end

      private def host_matches_domain?(host, domain)
        domain = domain.to_s.downcase
        return false if domain.blank?
        host == domain || host.end_with?(".#{domain}")
      end

      private def model_url_service
        @model_url_service ||= GitHub::Migrator::ModelUrlService.new
      end
    end
  end
end
