# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseOutsideCollaborators < Resolvers::Base
      argument :login, String, "The login of one specific outside collaborator.",
        required: false
      argument :query, String, "The search string to look for.", required: false
      argument :order_by, Inputs::EnterpriseMemberOrder,
        "Ordering options for outside collaborators returned from the connection.",
        required: false, default_value: { field: "login", direction: "ASC" }
      argument :visibility, Enums::RepositoryVisibility,
        "Only return outside collaborators on repositories with this visibility.",
        required: false
      argument :has_two_factor_enabled, Boolean,
        "Only return outside collaborators with this two-factor authentication status.",
        required: false,
        default_value: nil
      argument :organization_logins, [String], "Only return outside collaborators within the organizations with these logins", required: false

      type Platform::Connections::EnterpriseOutsideCollaborator, null: false

      def resolve(login: nil, query: nil, order_by: nil, visibility: nil, has_two_factor_enabled: nil, organization_logins: nil)
        ensure_business_can_use_api!(object)
        business_full_plan_required!(object)

        collaborators = if context[:permission].can_list_business_outside_collaborators?(object)
          object.filtered_outside_collaborators \
            login: login,
            query: query,
            order_by_field: order_by&.dig(:field),
            order_by_direction: order_by&.dig(:direction),
            visibility: repository_visibilities_argument(visibility),
            two_factor: user_two_factor_statuses_argument(has_two_factor_enabled),
            organizations: organization_logins
        else
          User.none
        end

        Promise.resolve(ArrayWrapper.new(collaborators))
      end

      def repository_visibilities_argument(visibility)
        case visibility
        when T.must(::Platform::Enums::RepositoryVisibility.values["PUBLIC"]).value
          [:public]
        when T.must(::Platform::Enums::RepositoryVisibility.values["PRIVATE"]).value
          [:private]
        when T.must(::Platform::Enums::RepositoryVisibility.values["INTERNAL"]).value
          [:internal]
        else
          [:public, :private, :internal]
        end
      end

      def user_two_factor_statuses_argument(has_two_factor_enabled)
        case has_two_factor_enabled
        when true
          :enabled
        when false
          :disabled
        else
          nil
        end
      end

    end
  end
end
