# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module AuditLog
      class JsonAuditEntry < Platform::Objects::AuditLog::Base
        description "Audit log entry with property containing all its fields serialized as JSON"

        visibility :internal
        minimum_accepted_scopes ["site_admin"]

        # Determine whether the viewer can access this object via the API (called internally).
        # This is where Egress checks for OAuth scopes and GitHub Apps go.
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_api_can_access?(permission, _object)
          # TODO write proper permissions before making this object public
          permission.hidden_from_public?(self)
        end

        # Determine whether the viewer can see this object (called internally).
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_viewer_can_see?(permission, object)
          Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
        end

        implements_node_with_document_id(prefix: "JAE")

        field :private, Boolean, null: false, description: "Whether this entry represents an action on a private repo"
        def private
          check_private_repo(&:itself)
        end

        field :locked, Boolean, null: false, description: "Whether fields in this entry have been nulled due to privacy lock"
        def locked
          check_locked(&:itself)
        end

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
          nil_if_locked { Loaders::ActiveRecord.load(::User, @object.get(:actor_id)) }
        end

        field :actor_database_id, Integer, null: true, description: "The database ID the user who initiated the action"
        def actor_database_id
          nil_if_locked { @object.get :actor_id }
        end

        field :actor_login, String, null: true, description: "The username of the user who initiated the action"
        def actor_login
          nil_if_locked { @object.get :actor }
        end

        field :actor_ip, String, null: true, description: "The IP address of the actor"
        def actor_ip
          nil_if_locked { @object.get :actor_ip }
        end

        field :actor_location, Platform::Objects::AuditLog::ActorLocation, null: true, description: "A readable representation of the actor's location"
        def actor_location
          nil_if_locked { @object }
        end

        field :actor_session_database_id, Integer, null: true, description: "The ID of session in which the action was triggered"
        def actor_session_database_id
          nil_if_locked { @object.get :actor_session }
        end

        field :client_id, String, null: true, description: "The client ID of the application"
        def client_id
          nil_if_locked { @object.get :client_id }
        end

        field :from, String, null: true, description: "The controller and action that initiated the logged action (e.g. stafftools/search#audit_log)"
        def from
          nil_if_locked { @object.get :from }
        end

        field :method, String, null: true, description: "The HTTP method used to visit the controller that initiated the action", resolver_method: :http_method
        def http_method
          nil_if_locked { @object.get :method }
        end

        field :request_category, String, null: true, description: "Help, what am I?"
        def request_category
          nil_if_locked { @object.get :request_category }
        end

        field :request_id, String, null: true, description: "The ID of the request that initiated the action"
        def request_id
          nil_if_locked { @object.get :request_id }
        end

        field :scopes, [String], null: true, description: "A list of the scopes that describe the type of access required to perform this action"
        def scopes
          nil_if_locked { @object.get :scopes }
        end

        field :server_id, String, null: true, description: "The ID of the server that received the request"
        def server_id
          nil_if_locked { @object.get :server_id }
        end

        field :staff_actor, Platform::Objects::User, null: true, description: "The staff user who initiated the action"
        def staff_actor
          nil_if_locked { Loaders::ActiveRecord.load(::User, @object.get(:staff_actor_id)) }
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

        field :url, Scalars::URI, null: true, description: "The URL visited to initiate this action"
        def url
          nil_if_locked { @object.get :url }
        end

        field :user, Platform::Objects::User, null: true, description: "The user affected by the action"
        def user
          nil_if_locked { Loaders::ActiveRecord.load(::User, @object.get(:user_id)) }
        end

        field :user_database_id, Integer, null: true, description: "The database ID of the user."
        def user_database_id
          nil_if_locked { @object.get :user_id }
        end

        field :user_login, String, null: true, description: "For actions involving two users, the actor is the initiator and the user is the affected user."
        def user_login
          nil_if_locked { @object.get :user }
        end

        field :user_agent, String, null: true, description: "The user agent that initiated the action"
        def user_agent
          nil_if_locked { @object.get :user_agent }
        end

        field :json_fields, String, null: true, description: "All fields of entry encoded as JSON"
        def json_fields
          check_locked do |is_locked|
            if is_locked
              @object.to_json(only: %w[action created_at])
            else
              @object.to_json
            end
          end
        end

        private

        # Evaluates block and returns result if any of the following are true, otherwise returns nil:
        #   1. The entry does not represent an event on a repo
        #   2. The entry's repo is public
        #   3. The viewer has unlocked access to the entry's actor
        def nil_if_locked
          check_locked { |is_locked| yield unless is_locked }
        end

        def check_locked
          check_private_repo do |is_private|
            if is_private
              check_actor_unlocked do |is_unlocked|
                yield(!is_unlocked)
              end
            else
              yield(false)
            end
          end
        end

        # Based on https://github.com/github/github/blob/40abe491894e6ecfbf7dd0f74985b0fb78dff236/app/view_models/stafftools/search/audit_log_view.rb#L262-L266.
        # We return early and skip the DB call if the visibility data is present on the event itself.
        def check_private_repo
          repo_id = @object.get :repo_id
          visibility = @object.dig(:data, :visibility)

          return yield(false) if repo_id.blank?
          return yield(false) if visibility == "public"
          return yield(true) if visibility == "private"

          Loaders::ActiveRecord.load(::Repository, repo_id, security_violation_behaviour: :nil).then do |repo|
            if repo.present?
              yield(repo.private?)
            else
              yield(true)
            end
          end
        end

        def check_actor_unlocked
          actor_id = @object.get :actor_id
          viewer = @context[:viewer]

          return yield(true) if actor_id.blank? || viewer.id == actor_id

          Loaders::ActiveRecord.load(::User, actor_id, security_violation_behaviour: :nil).then do |actor|
            if actor.present?
              yield(viewer.can_access_private_audit_logs_for?(actor))
            else
              yield(true)
            end
          end
        end
      end
    end
  end
end
