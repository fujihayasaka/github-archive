# typed: strict
# frozen_string_literal: true

module ScopedInstallations
  module AuthorizationDetails
    module Loaders
      class Permission
        extend T::Sig

        include LoadActorDependency
        include Repositories::Domain::Provider
        include Scientist

        PARENT_ABILITY_TYPE   = "IntegrationInstallation"
        TRACER_SPAN_NAMESPACE = "ScopedInstallations::AuthorizationDetails::Loaders::Permission"

        PermissionTriple = T.type_alias do
          [Integer, Integer, Integer]
        end

        sig do
          params(
            actor_type: String,
            actor_id: Integer,
            subject_type: String,
            subject_ids: T::Array[Integer]
          ).returns(T::Array[PermissionTriple])
        end
        def self.load(actor_type, actor_id, subject_type, subject_ids)
          new(actor_type, actor_id, subject_type, subject_ids).perform
        end

        sig do
          params(
            actor_type: String,
            actor_id: Integer,
            subject_type: String,
            subject_ids: T::Array[Integer]
          ).void
        end
        def initialize(actor_type, actor_id, subject_type, subject_ids)
          @actor_type = actor_type
          @actor_id = actor_id
          @subject_type = subject_type
          @subject_ids = subject_ids

          @actor = T.let(nil, T.nilable(Actor))
          @name = T.let(T.must(@subject_type.split("/").last), String)
          @resource_type = T.let(T.must(ResourceType.from_subject_type(@subject_type)), ResourceType)

          @parent_ability_id = T.let(nil, T.nilable(Integer))

          @details = T.let(nil, T.nilable(T.any(Structs::V1, Structs::V2)))
        end

        sig { returns(T::Array[PermissionTriple]) }
        def perform
          GitHub.tracer.in_span("#{TRACER_SPAN_NAMESPACE}#perform", kind: :internal) do |_span|
            @actor = load_actor(@actor_type, @actor_id)

            case @actor_type
            when "GlobalIntegrationInstallation"
              # Do not use the science experiement for global installations.
              return @actor.present? ? fetch_permissions_from_authorization_details : []
            end

            case @actor
            when ScopedIntegrationInstallation
              @parent_ability_id = @actor.integration_installation_id
            end

            science "authorization_details_loaders_permissions" do |e|
              e.context({
                actor_id: @actor_id,
                actor_type: @actor_type,
                subject_type: @subject_type,
                subject_ids: @subject_ids,
              })

              e.run_if { @actor&.authorization_details_applicable? }

              e.use { fetch_permissions_from_sql(actor_type: @actor_type, actor_id: @actor_id, subject_type: @subject_type, subject_ids: @subject_ids) }
              e.try { fetch_permissions_from_authorization_details }

              e.compare do |control, candidate|
                control.sort == candidate.sort
              end
            end
          end
        end

        private

        sig do
          params(
            actor_type: String,
            actor_id: Integer,
            subject_type: String,
            subject_ids: T::Array[Integer]
          ).returns(T::Array[PermissionTriple])
        end
        def fetch_permissions_from_sql(actor_type:, actor_id:, subject_type:, subject_ids:)
          GitHub.tracer.in_span("#{TRACER_SPAN_NAMESPACE}#fetch_permissions_from_sql", kind: :internal) do |span|
            span.set_attribute("gh.installation.type", actor_type)
            span.set_attribute("gh.installation.id", actor_id)

            span.set_attribute("gh.subject.type", subject_type)
            span.set_attribute("gh.subject.ids.count", subject_ids.count)

            ::Permission.where(
              actor_type: actor_type,
              subject_type: subject_type,
              actor_id: actor_id,
              subject_id: subject_ids,
            ).pluck(
              :actor_id, :subject_id, :action,
            ).map do |actor_id, subject_id, action|
              # Because consumers of this method expect the action value to be an integer,
              # we need to explicitly convert it here.
              [actor_id, subject_id, ::Permission.actions[action]]
            end
          end
        end

        sig { returns(T::Array[PermissionTriple]) }
        def fetch_permissions_from_authorization_details
          GitHub.tracer.in_span("#{TRACER_SPAN_NAMESPACE}#fetch_permissions_from_authorization_details", kind: :internal) do |_span|
            return [] if @actor.nil?

            @details = @actor.authorization_details_struct

            if Permissions::ResourceRegistry.individual_type_prefixed_subject_types.include?(@subject_type)
              fetch_individual_type_permissions
            elsif Permissions::ResourceRegistry.all_type_prefixed_subject_types.include?(@subject_type)
              fetch_all_type_permissions
            else
              # If the resource registry doesn't recognize the subject type, return nothing.
              []
            end
          end
        end

        sig { returns(T::Array[PermissionTriple]) }
        def fetch_all_type_permissions
          return [] if @details.nil?

          action = @details.granted_access_on_all_subjects(@resource_type, @name)
          return [] if action.nil?

          case @details.selection_for(@resource_type)
          when Selection::Global
            # Special exception, because we don't care about the target for the global selection.
            map_with_actor(@subject_ids.each_with_object({}) { |subject_id, hash| hash[subject_id] = action })
          else
            # We only allow access to the target when granting on 'all' subjects.
            subject_ids = @subject_ids.filter { |subject_id| subject_id == T.must(@actor).target_id }
            return [] if subject_ids.empty?

            unless @actor.is_a?(ScopedIntegrationInstallation)
              return map_with_actor({ T.must(@actor).target_id => action })
            end

            subject_ids_and_actions_limited_by_parent({ @actor.target_id => action })
          end
        end

        sig { returns(T::Array[PermissionTriple]) }
        def fetch_individual_type_permissions
          return [] if @details.nil?

          granted_subject_ids_with_actions = @details.granted_subject_ids_with_actions_for(
            @resource_type, @name, @subject_ids
          )

          return [] if granted_subject_ids_with_actions.empty?
          granted_subject_ids_with_actions = granted_subject_ids_with_actions.to_h

          # 'Public' scoped installations are always limited by the
          # 'parent' installation in order to avoid escalation of privilege.
          #
          # We used to do this by updating all of the scoped installations
          # in a background job, but since we don't want to update the JSON
          # all the time we evaluate it at runtime.
          unless @actor.is_a?(ScopedIntegrationInstallation)
            return map_with_actor(granted_subject_ids_with_actions)
          end

          case @resource_type
          when ResourceType::Repository
            if (parent_access_on_all = parent_access_granted_repository_access_on_all(@name))
              case @details.selection_for(@resource_type)
              when Selection::Subset
                # Filter the subject ids to only ones that match the target.
                #
                # This prevents cross target repository selection for scoped
                # installations, which is not currently allowed.
                repository_ids =
                  ActiveRecord::Base.connected_to(role: :reading) do
                    repositories_domain.repo_ids_by_owner(
                      owner_id: @actor.target_id,
                      public_only: false,
                      repo_ids_in: granted_subject_ids_with_actions.keys
                    )
                  end

                map_with_actor(
                  repository_ids.each_with_object({}) do |repository_id, hash|
                    details_action = granted_subject_ids_with_actions[repository_id]
                    next if details_action.nil?

                    # Take the lowest granted action between the actor and the
                    # parent to avoid privilege escalation.
                    min_action = [details_action, parent_access_on_all].min

                    hash[repository_id] = min_action
                  end
                )
              else
                # For any other access, we don't have access to a subset
                # so the permission is invalid.
                []
              end
            else
              subject_ids_and_actions_limited_by_parent(granted_subject_ids_with_actions)
            end
          else
            subject_ids_and_actions_limited_by_parent(granted_subject_ids_with_actions)
          end
        end

        sig { params(subject_ids_with_actions: T::Hash[Integer, Integer]).returns(T::Array[PermissionTriple]) }
        def map_with_actor(subject_ids_with_actions)
          subject_ids_with_actions.map do |subject_id, action|
            [@actor_id, subject_id, action]
          end
        end

        sig { params(name: String).returns(T.nilable(Integer)) }
        def parent_access_granted_repository_access_on_all(name)
          GitHub.tracer.in_span("#{TRACER_SPAN_NAMESPACE}#parent_access_granted_repository_access_on_all", kind: :internal) do |_span|
            subject = T.must(@actor).target.repository_resources.public_send(@name) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod

            ActiveRecord::Base.connected_to(role: :reading) do
              permissions = fetch_permissions_from_sql(
                actor_type: PARENT_ABILITY_TYPE,
                actor_id: T.must(@parent_ability_id),
                subject_type: subject.ability_type,
                subject_ids: [subject.ability_id]
              )

              permissions.first&.last
            end
          end
        end

        sig do
          params(
            subject_ids_and_actions: T::Hash[Integer, Integer],
          ).returns(T::Array[PermissionTriple])
        end
        def subject_ids_and_actions_limited_by_parent(subject_ids_and_actions)
          GitHub.tracer.in_span("#{TRACER_SPAN_NAMESPACE}#subject_ids_and_actions_limited_by_parent", kind: :internal) do |_span|
            parent_permissions =
              ActiveRecord::Base.connected_to(role: :reading) do
                fetch_permissions_from_sql(
                  actor_type: PARENT_ABILITY_TYPE,
                  actor_id: T.must(@parent_ability_id),
                  subject_type: @subject_type,
                  subject_ids: subject_ids_and_actions.keys
                )
              end

            map_with_actor(
              parent_permissions.each_with_object({}) do |(_, subject_id, action), hash|
                details_action = subject_ids_and_actions[subject_id]
                next if details_action.nil?

                # Take the lowest granted action between the actor and the
                # parent to avoid privilege escalation.
                min_action = [details_action, action].min

                hash[subject_id] = min_action
              end
            )
          end
        end
      end
    end
  end
end
