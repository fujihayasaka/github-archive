# typed: strict
# frozen_string_literal: true

module Authz
  class Domain
    class UserRoles < GH::Domain::Base
      # Public: Fetch all-repository roles for a given actor type and actor IDs for a given target.
      #
      # target     - The target organization for the role check.
      # actor_type - The type of the actor (e.g., User, Team).
      # actor_ids  - An array of actor IDs to check for roles.
      #
      # Returns a hash mapping actor types to an array of actor IDs that have roles.
      sig do
        params(
          target: Organization,
          actor_type: String,
          actor_ids: T::Array[Integer]
        ).returns(T::Hash[String, T::Array[Integer]])
      end
      def all_repo_roles_for_actor(target:, actor_type:, actor_ids:)
        return {} if actor_ids.empty?

        # Handle business target conditions if feature is enabled
        query = if target.business&.erp_feature_enabled?(:enterprise_teams_esm)
          where_target_business_or_org(target: target, actor_type: actor_type, actor_ids: actor_ids)
        else
          where_target_org(target: target, actor_type: actor_type, actor_ids: actor_ids)
        end

        # Join with roles and role_permissions for base repo permission
        query = with_base_role_repo_permission_action(query).distinct

        results = query.pluck(:actor_id, :actor_type)
        map_actor_type_to_actor_ids(results)
      end

      private

      sig do
        params(
          target: Organization,
          actor_type: String,
          actor_ids: T::Array[Integer]
        ).returns(ActiveRecord::Relation)
      end
      def where_target_org(target:, actor_type:, actor_ids:)
        UserRole.where(
            actor_type: actor_type,
            actor_id: actor_ids,
            target_type: "Organization",
            target_id: target.id
          )
      end

      sig do
        params(
          target: Organization,
          actor_type: String,
          actor_ids: T::Array[Integer]
        ).returns(ActiveRecord::Relation)
      end
      def where_target_business_or_org(target:, actor_type:, actor_ids:)
        business_id = T.must(target.business).id

        # Create organization condition query
        org_condition = { target_type: "Organization", target_id: target.id }
        org_query = where_target_org(target: target, actor_type: actor_type, actor_ids: actor_ids)

        # Create business condition query with the same actor constraints
        business_query = UserRole.where(target_type: "Business", target_id: business_id)
                                .where(actor_type: actor_type, actor_id: actor_ids)
                                .where(
                                  "conditions_target = 'all_orgs' OR (conditions_target = 'some_orgs' AND CAST(? AS UNSIGNED) MEMBER OF (conditions_target_ids))",
                                  target.id.to_s
                                )

        org_query.or(business_query)
      end

      sig { params(query: ActiveRecord::Relation).returns(ActiveRecord::Relation) }
      def with_base_role_repo_permission_action(query)
        query
          .joins("INNER JOIN roles ON user_roles.role_id = roles.id")
          .joins("INNER JOIN role_permissions ON role_permissions.role_id = roles.base_role_id")
          .where("role_permissions.action IN ('read_repo', 'write_repo', 'admin_repo')")
      end

      sig { params(rows: T::Array[[Integer, String]]).returns(T::Hash[String, T::Array[Integer]]) }
      def map_actor_type_to_actor_ids(rows)
        rows.each_with_object({}) do |(actor_id, actor_type), map|
          map[actor_type] ||= []
          map[actor_type] << actor_id
        end
      end
    end
  end
end
