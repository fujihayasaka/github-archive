# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module AuditLog
      module AuditEntry
        include Platform::Interfaces::Base

        description "An entry in the audit log."

        field :action, String, null: false, description: "The action name"
        def action
          @object.get :action
        end

        field :operation_type, Platform::Enums::AuditLog::OperationType, null: true, description: "The corresponding operation type for the action"
        def operation_type
          @object.get :operation_type
        end

        field :actor, Platform::Unions::AuditLog::AuditEntryActor, null: true, description: "The user who initiated the action"
        def actor
          Loaders::ActiveRecord.load(::User, @object.get(:actor_id))
        end

        field :actor_database_id, Integer, null: true, visibility: :internal, description: "The database ID the user who initiated the action"
        def actor_database_id
          @object.get :actor_id
        end

        field :actor_login, String, null: true, description: "The username of the user who initiated the action"
        def actor_login
          @object.get :actor
        end

        field :actor_ip, String, null: true, description: "The IP address of the actor"
        def actor_ip
          if viewer_is_actor?
            @object.get :actor_ip
          else
            nil # only show actor ip when viewer is the actor, or viewer is staff
          end
        end

        url_fields prefix: :actor, null: true, description: "The HTTP URL for the actor." do |audit_entry|
          Loaders::ActiveRecord.load(::User, audit_entry.get(:actor_id)).then do |actor|
            actor&.permalink(include_host: false)
          end
        end

        field :actor_location, Platform::Objects::AuditLog::ActorLocation, null: true, description: "A readable representation of the actor's location"
        def actor_location
          @object
        end

        field :actor_session_database_id, Integer, null: true, visibility: :internal, description: "The ID of session in which the action was triggered"
        def actor_session_database_id
          @object.get :actor_session
        end

        field :client_id, String, null: true, visibility: :internal, description: "The client ID of the application"
        def client_id
          @object.get :client_id
        end

        field :external_identity_guid, String, null: true, visibility: :internal, description: "The ID of the actor's external identity"
        def external_identity_guid
          @object.get :external_identity_guid
        end

        field :external_identity_nameid, String, null: true, visibility: :internal, description: "Help, what am i?"
        def external_identity_nameid
          @object.get :external_identity_nameid
        end

        field :external_identity_username, String, null: true, visibility: :internal, description: "The username of the actor's external identity"
        def external_identity_username
          @object.get :external_identity_username
        end

        field :from, String, null: true, visibility: :internal, description: "The controller and action that initiated the logged action (e.g. stafftools/search#audit_log)"
        def from
          @object.get :from
        end

        field :method, String, null: true, visibility: :internal, description: "The HTTP method used to visit the controller that initiated the action", resolver_method: :http_method
        def http_method
          @object.get :method
        end

        field :oauth_access_database_id, Integer, null: true, visibility: :internal, description: "Help, what am I?"
        def oauth_access_database_id
          @object.get :oauth_access_id
        end

        field :oauth_application_database_id, Integer, null: true, visibility: :internal, description: "The ID of the associated OAuth application"
        def oauth_application_database_id
          @object.get :oauth_application_id
        end

        field :oauth_scopes, String, null: true, visibility: :internal, description: "Help, what am I?"
        def oauth_scopes
          @object.get :oauth_scopes
        end

        field :referrer, String, null: true, visibility: :internal, description: "Help, what am I?"
        def referrer
          @object.get :referrer
        end

        field :request_category, String, null: true, visibility: :internal, description: "Help, what am I?"
        def request_category
          @object.get :request_category
        end

        field :request_id, String, null: true, visibility: :internal, description: "The ID of the request that initiated the action"
        def request_id
          @object.get :request_id
        end

        field :scopes, [String], null: true, visibility: :internal, description: "A list of the scopes that describe the type of access required to perform this action"
        def scopes
          @object.get :scopes
        end

        field :server_id, String, null: true, visibility: :internal, description: "The ID of the server that received the request"
        def server_id
          @object.get :server_id
        end

        field :staff_actor, Platform::Objects::User, null: true, visibility: :internal, description: "The staff user who initiated the action"
        def staff_actor
          if viewer_is_staff?
            Loaders::ActiveRecord.load(::User, @object.get(:staff_actor_id))
          else
            nil # don't show this if the viewer isn't staff
          end
        end

        field :created_at, Scalars::PreciseDateTime, null: false, description: "The time the action was initiated"
        def created_at
          # An AuditEntry record or Audit::Elastic::Hit need to have the same
          # interface for accessing the objects created_at timestamp.
          #
          # An Audit::Elastic::Hit will have a value at @object["created_at"]
          # but it isn't the one we want to use. GraphQL Ruby tries to see if
          # @object responds like a Hash and has a value at the created_at key.
          # This object that is true, but it is an integer at that point not a
          # Time object.
          @object.created_at
        end

        field :url, Scalars::URI, null: true, visibility: :internal, description: "The URL visited to initiate this action"
        def url
          @object.get :url
        end

        field :user, Platform::Objects::User, null: true, description: "The user affected by the action"
        def user
          Loaders::ActiveRecord.load(::User, @object.get(:user_id))
        end

        field :user_database_id, Integer, null: true, visibility: :internal, description: "The database ID of the user."
        def user_database_id
          @object.get :user_id
        end

        field :user_login, String, null: true, description: "For actions involving two users, the actor is the initiator and the user is the affected user."
        def user_login
          @object.get :user
        end

        url_fields prefix: :user, null: true, description: "The HTTP URL for the user." do |audit_entry|
          Loaders::ActiveRecord.load(::User, audit_entry.get(:user_id)).then do |user|
            user&.permalink(include_host: false)
          end
        end

        field :user_agent, String, null: true, visibility: :internal, description: "The user agent that initiated the action"
        def user_agent
          @object.get :user_agent
        end

        field :can_render_user_avatar, Boolean, visibility: :internal, null: false, description: "Determines if the user avatar can be rendered"
        def can_render_user_avatar
          actor = @object.get(:actor)
          user = @object.get(:user)
          org = @object.get(:org)

          actor != user && user != org
        end

        private

        def viewer_is_actor?
          T.bind(self, GraphQL::Schema::Object)
          context[:viewer].id == @object.get(:actor_id)
        end

        def viewer_is_staff?
          T.bind(self, Platform::Objects::Base).class.viewer_is_site_admin?(context[:viewer], self.class.name)
        end
      end
    end
  end
end
