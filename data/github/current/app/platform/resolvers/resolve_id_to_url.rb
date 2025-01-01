# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class ResolveIdToUrl < Resolvers::Base
      type Scalars::URI, null: true

      argument :id, ID, "The Global Relay ID to resolve to a URL.", required: true

      def resolve(id:)
        unless Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(context[:viewer], self.class.name)
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to resolve Global Relay ID to a URL.")
        end

        raise Platform::Errors::NotFound, "Could not resolve to a node with the global id of 'nil'." if id.nil?

        parsed = Platform::Helpers::GlobalId.parse(id)

        type = Platform::Schema.get_type(parsed.type)
        return Promise.resolve(nil) unless type

        model_promise = if parsed.is_a?(Platform::Helpers::GlobalId::Next)
          type.load_from_next_global_id(parsed)
        else
          type.load_from_global_id(parsed.id)
        end

        model_promise.then do |object|
          model_url_service.url_for_model(object)
        end
      end

      private def model_url_service
        @model_url_service ||= GitHub::Migrator::ModelUrlService.new
      end
    end
  end
end
