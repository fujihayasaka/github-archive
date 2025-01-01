# typed: false
# frozen_string_literal: true

module Platform
  module Interfaces
    module AvatarOwner
      include Platform::Interfaces::Base
      description "An entity that has an avatar"
      visibility :under_development

      field :avatars, Connections.define(Objects::Avatar),
        description: "The avatars of the user",
        null: true,
        visibility: :under_development,
        connection: true,
        minimum_accepted_scopes: ["site_admin"]

      def avatars
        unless @context[:viewer].site_admin?
          raise Errors::Forbidden.new("#{@context[:viewer].display_login} does not have permission to retrieve avatars.")
        end

        @object.avatars
      end

    end
  end
end
