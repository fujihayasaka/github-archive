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

        model_url_service.model_for_url(url)
      end

      private def model_url_service
        @model_url_service ||= GitHub::Migrator::ModelUrlService.new
      end
    end
  end
end
