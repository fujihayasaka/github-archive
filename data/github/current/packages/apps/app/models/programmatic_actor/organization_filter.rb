# typed: true
# frozen_string_literal: true

module ProgrammaticActor
  class OrganizationFilter
    class << self
      # Public: Determine if the filter will actually filter repositories.
      #
      # Returns a Boolean.
      def applicable?(actor)
        return false unless actor.instance_of?(User)
        actor.using_auth_via_integration? || actor.using_auth_via_user_programmatic_access?
      end

      def perform(actor:, organization_ids: [], resource:)
        GitHub.tracer.in_span("programmatic_actor.organization_filter.perform", kind: :internal) do |span|
          return [] if organization_ids.empty?

          subject_type = Organization::Resources.all_prefixed_subject_types([resource]).first
          return [] unless subject_type

          span.add_attributes(
            "gh.programmatic_actor.id" => actor.id,
            "gh.programmatic_actor.type" => auth_type(actor),
            "gh.programmatic_actor_filter.organizations.count" => organization_ids.count,
            "gh.programmatic_actor_filter.resource" => resource
          )

          if actor.using_auth_via_integration?
            accessible_organizations_via_integration(
              actor: actor, organization_ids: organization_ids, subject_type: subject_type,
            )
          elsif actor.using_auth_via_user_programmatic_access?
            accessible_organizations_via_user_programmatic_access(
              actor: actor, organization_ids: organization_ids, subject_type: subject_type,
            )
          else
            organization_ids
          end
        end
      end

      private

      def accessible_organizations_via_integration(actor:, organization_ids:, subject_type:)
        oauth_access = actor.oauth_access

        if (installation = oauth_access.installation)
          resource = subject_type.split("/").last # Organization/members => members
          org_ids_with_permission = installation.organization_ids(resource:)

          return org_ids_with_permission.intersection(organization_ids)
        end

        integration = oauth_access.application
        accessible_org_ids = T.let([], T::Array[Integer])

        organization_ids.each_slice(1000) do |org_ids|
          installation_ids = integration.installations.with_target_id_type(org_ids, "User").pluck(:id)
          next if installation_ids.empty?

          # Batch the number of installation ids we can send at once.
          accessible_org_ids += Permission.where(
            actor_id: installation_ids,
            actor_type: "IntegrationInstallation",
            subject_type: subject_type,
          ).pluck(:subject_id)
        end

        accessible_org_ids
      end

      def accessible_organizations_via_user_programmatic_access(actor:, organization_ids:, subject_type:)
        grant = actor.programmatic_access.grant
        return [] unless grant

        Permission.where(
          actor_id: grant.ability_id,
          actor_type: grant.ability_type,
          subject_type: subject_type
        ).pluck(:subject_id)
      end

      def auth_type(actor)
        if actor.using_auth_via_integration?
          "user_to_server"
        elsif actor.using_auth_via_user_programmatic_access?
          "user_programmatic_access"
        else
          "unknown"
        end
      end
    end
  end
end
