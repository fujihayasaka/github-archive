# typed: true
# frozen_string_literal: true

require "monolith-twirp-licensing-customers"

module Api::Internal::Twirp::Licensing
  module Customers
    module V1
      # Handler for the MonolithTwirp::Licensing::Customers::V1::UsersAPIService
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        extend T::Sig

        allow_access_for :client, allowed_clients: ["licensing"]
        handles_service MonolithTwirp::Licensing::Customers::V1::UsersAPIService

        ORGS_LIMIT = 5000

        # Public: Implementation of the GetUsers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::Customers::V1::GetUsersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Licensing::Customers::V1::GetUsersResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::Customers::V1::GetUsersRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetUsersResponse, Twirp::Error))
        end
        def get_users(req, env)
          if req.entity_type == :ENTITY_TYPE_INVALID
            return Twirp::Error.invalid_argument("entity_type is required", argument: "entity_type")
          end

          unless entity_id = id_argument(req.entity_id)
            return Twirp::Error.invalid_argument("entity_id is required", argument: "entity_id")
          end

          # Organization requested
          if req.entity_type == :ENTITY_TYPE_ORGANIZATION
            return handle_org_entity(entity_id)
          end

          # Customer requested
          handle_customer_entity(entity_id, req.page_token)
        end

        private

        sig { params(org_id: Integer).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetUsersResponse, Twirp::Error)) }
        def handle_org_entity(org_id)
          unless organization = Organization.find_by(id: org_id)
            return Twirp::Error.not_found("organization not found")
          end

          unless organization.active?
            return Twirp::Error.not_found("organization deleted")
          end

          org_memberships_by_user = organization.member_ids.each_with_object({}) do |user_id, result|
            result[user_id] ||= [org_id]
          end

          users = build_users_list(org_memberships_by_user, {})

          MonolithTwirp::Licensing::Customers::V1::GetUsersResponse.new(
            customer_id: organization.licensed_customer_id,
            users: users,
          )
        end

        sig { params(customer_id: Integer, page_token: String).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetUsersResponse, Twirp::Error)) }
        def handle_customer_entity(customer_id, page_token)
          unless customer = Customer.find_by(id: customer_id)
            return Twirp::Error.not_found("customer not found")
          end

          users = []
          next_page_token = ""
          if customer.business.present?
            users, next_page_token = get_users_for_business_customer(customer, page_token)
          elsif customer.organizations.present?
            users, next_page_token = get_users_for_org_customer(customer)
          end

          MonolithTwirp::Licensing::Customers::V1::GetUsersResponse.new(
            customer_id: customer.id,
            users: users,
            next_page_token: next_page_token,
          )
        end

        sig { params(customer: Customer).returns([T::Array[MonolithTwirp::Licensing::Customers::V1::User], String]) }
        def get_users_for_org_customer(customer)
          orgs = customer.organizations.filter do |org|
            org.active? && !org.is_organization_billed_through_business?
          end

          org_memberships_by_user = orgs.each_with_object({}) do |org, result|
            org.member_ids.map do |user_id|
              result[user_id] ||= []
              result[user_id] << T.must(org.id)
            end
            result
          end

          repo_memberships_by_user = get_repo_memberships(orgs.pluck(:id))

          users = build_users_list(org_memberships_by_user, repo_memberships_by_user)

          [users, ""]
        end

        sig { params(customer: Customer, page_token: String).returns([T::Array[MonolithTwirp::Licensing::Customers::V1::User], String]) }
        def get_users_for_business_customer(customer, page_token)
          users = []
          cursor = page_token.to_i
          next_cursor = ""

          all_org_ids = T.must(customer.business).organizations
            .where("users.id > ?", cursor)
            .order("users.id asc")
            .reject { |org| org.deleted? }
            .pluck(:id)

          is_last_page = all_org_ids.size <= ORGS_LIMIT
          page_ids = all_org_ids.first(ORGS_LIMIT)

          if page_ids.any?
            org_and_user_ids = T.must(customer.business).business_org_abilities(org_ids: page_ids).pluck(:subject_id, :actor_id) || []
            org_memberships_by_user = org_and_user_ids.each_with_object(Hash.new { |h, user_id| h[user_id] = [] }) do |(org_id, user_id), memo|
              memo[user_id] << org_id
            end

            repo_memberships_by_user = get_repo_memberships(page_ids)

            users = build_users_list(org_memberships_by_user, repo_memberships_by_user)

            next_cursor = page_ids.last.to_s unless is_last_page
          end

          [users, next_cursor]
        end

        sig { params(org_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[Integer]]) }
        def get_repo_memberships(org_ids)
          advisory_workspace_repo_ids = RepositoryAdvisory
            .where(owner_id: org_ids)
            .where.not(workspace_repository_id: nil)
            .pluck(:workspace_repository_id)

          repo_ids = Repository.active.private_scope.not_forks
            .where(organization_id: org_ids)
            .where.not(id: advisory_workspace_repo_ids)
            .pluck(:id)

          user_and_repo_id_pairs = ::Ability.from("abilities FORCE INDEX(subject_and_actor_and_priority_and_action)").batched_scope(:subject_id, values: repo_ids) do |scope|
            scope.where(
              subject_type: "Repository",
              actor_type: "User",
              priority: Ability.priorities[:direct],
            ).distinct
          end.pluck(:actor_id, :subject_id)

          user_and_repo_id_pairs.group_by(&:first).transform_values do |pairs|
            pairs.map(&:last)
          end
        end

        sig do
          params(
            org_memberships_by_user: T::Hash[Integer, T::Array[Integer]],
            repo_memberships_by_user: T::Hash[Integer, T::Array[Integer]]
          ).returns(T::Array[MonolithTwirp::Licensing::Customers::V1::User])
        end
        def build_users_list(org_memberships_by_user, repo_memberships_by_user)
          merged = Hash.new { |h, user_id| h[user_id] = MonolithTwirp::Licensing::Customers::V1::User.new(id: user_id) }
          org_memberships_by_user.each do |user_id, org_ids|
            merged[user_id].organization_memberships += org_ids
          end
          repo_memberships_by_user.each do |user_id, repo_ids|
            merged[user_id].collaborating_repositories += repo_ids
          end
          merged.values
        end
      end
    end
  end
end
