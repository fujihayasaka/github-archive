# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Actor
      include Interfaces::Base
      include Platform::Authorization::ReauthorizeScopedObjects

      description "Represents an object which can take actions on GitHub. Typically a User or Bot."

      field :id, ID, method: :global_relay_id, null: false, description: "A unique identifier for this actor.", visibility: :under_development

      field :login, String, "The username of the actor.", null: false, method: :display_login_legacy
      field :display_name, String, "The display login of the actor.", null: false, method: :display_login, required_capabilities: [:mobile_only_schema_mask]
      field :name, String, "The name of the actor.", null: true, method: :name, visibility: :under_development

      field :avatar_url, Scalars::URI, "A URL pointing to the actor's public avatar.", null: false do
        argument :size, Integer, "The size of the resulting square image.", required: false
      end

      url_fields description: "The HTTP URL for this actor."
      url_fields prefix: :profile, description: "The HTTP URL linking to the actor's profile", visibility: :internal, null: true do |actor|
        if actor.bot?
          # async integration may resolve to nil
          actor.async_integration.then do |integration|
            if integration
              integration.async_public_app_path
            else
              next nil
            end
          end
        else
          template = Addressable::Template.new("/{login}")
          template.expand login: actor.display_login
        end
      end
    end
  end
end
