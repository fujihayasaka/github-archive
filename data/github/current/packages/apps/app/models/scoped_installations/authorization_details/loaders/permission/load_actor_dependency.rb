# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Loaders
      module Permission::LoadActorDependency
        extend T::Helpers

        Actor = T.type_alias do
          T.any(
            GlobalIntegrationInstallation,
            ScopedIntegrationInstallation,
            SiteScopedIntegrationInstallation
          )
        end

        requires_ancestor { Kernel }

        sig { params(actor_type: String, actor_id: Integer).returns(T.nilable(Actor)) }
        def load_actor(actor_type, actor_id)
          GitHub.tracer.in_span("ScopedInstallations::AuthorizationDetails::Loaders::Permission::LoadActorDependency#load_actor", kind: :internal) do |_span|
            case actor_type
            when "GlobalIntegrationInstallation"
              ActiveRecord::Base.connected_to(role: :reading) do
                integration = Integration.includes(latest_version: [:default_permission_records]).find_by(id: actor_id)
                return if integration.nil?

                # We have to re-build the object because we only store the
                # "actor id". The target here doesn't matter.
                GlobalIntegrationInstallation.new(integration, User.ghost)
              end
            when "ScopedIntegrationInstallation"
              load_scoped_integration_installation_actor(actor_id)
            when "SiteScopedIntegrationInstallation"
              load_site_scoped_integration_installation_actor(actor_id)
            else
              raise ArgumentError, "Unsupported actor type: #{actor_type}"
            end
          end
        end

        # Attempt to read the record from the replica, and then if we can't
        # find it query from the primary.
        #
        # Since the data being passed to us the primary id, chances are the
        # record exists.
        sig { params(actor_id: Integer, role: Symbol).returns(T.nilable(::ScopedIntegrationInstallation)) }
        def load_scoped_integration_installation_actor(actor_id, role: :reading)
          ActiveRecord::Base.connected_to(role:) do
            installation =
              case role
              when :writing
                sii = ScopedIntegrationInstallation.find_by(id: actor_id)

                # If we query the sii from the primary, we shouldn't also preload
                # the parent and target from the primary as well.
                #
                # These are settled records that don't have the same read/write
                # replication issues.
                ActiveRecord::Base.connected_to(role: :reading) do
                  sii&.parent; sii&.target
                end

                sii
              else
                ScopedIntegrationInstallation.includes(parent: [:target]).find_by(id: actor_id)
              end

            if installation.nil?
              return if role == :writing
              return load_scoped_integration_installation_actor(actor_id, role: :writing)
            end

            installation
          end
        end

        # Attempt to read the record from the replica, and then if we can't
        # find it query from the primary.
        #
        # Since the data being passed to us the primary id, chances are the
        # record exists.
        sig { params(actor_id: Integer, role: Symbol).returns(T.nilable(::SiteScopedIntegrationInstallation)) }
        def load_site_scoped_integration_installation_actor(actor_id, role: :reading)
          ActiveRecord::Base.connected_to(role:) do
            installation = SiteScopedIntegrationInstallation.find_by(id: actor_id)

            return installation if installation.present?
            return if role == :writing

            load_site_scoped_integration_installation_actor(actor_id, role: :writing)
          end
        end
      end
    end
  end
end
