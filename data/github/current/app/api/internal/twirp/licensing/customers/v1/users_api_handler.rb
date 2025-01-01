# typed: true
# frozen_string_literal: true

require "monolith-twirp-licensing-customers"

module Api::Internal::Twirp::Licensing
  module Customers
    module V1
      # Handler for the MonolithTwirp::Licensing::Customers::V1::UsersAPIService
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["licensing"]
        handles_service MonolithTwirp::Licensing::Customers::V1::UsersAPIService

        DEFAULT_ORGS_PAGE_SIZE = 5000

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
          page_size = req.page_size > 0 ? req.page_size : DEFAULT_ORGS_PAGE_SIZE
          handle_customer_entity(entity_id, req.page_token, page_size)
        end

        # Public: Implementation of the GetCustomer Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::Customers::V1::GetCustomerRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Licensing::Customers::V1::GetCustomer, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::Customers::V1::GetCustomerRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetCustomerResponse, Twirp::Error))
        end
        def get_customer(req, env)
          unless customer_id = id_argument(req.customer_id)
            return Twirp::Error.invalid_argument("customer_id is required", argument: "customer_id")
          end

          customer = Customer.find_by(id: customer_id)

          return Twirp::Error.not_found("customer not found") unless customer

          payload = MonolithTwirp::Licensing::Customers::V1::Customer.new(customer.to_licensify_customer_payload)
          MonolithTwirp::Licensing::Customers::V1::GetCustomerResponse.new(customer: payload)
        end

        private

        sig { params(org_id: Integer).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetUsersResponse, Twirp::Error)) }
        def handle_org_entity(org_id)
          unless organization = Organization.includes(:business).find_by(id: org_id)
            return Twirp::Error.not_found("organization not found")
          end

          unless organization.active?
            return Twirp::Error.not_found("organization deleted")
          end

          org_memberships_by_user = organization.member_ids.each_with_object({}) do |user_id, result|
            result[user_id] ||= [org_id]
          end

          suspended_users = if organization.business.present?
            get_suspended_users_for_business(T.must(organization.business), org_memberships_by_user.keys)
          else
            {}
          end

          users = build_users_list(org_memberships_by_user, {}, suspended_users)

          MonolithTwirp::Licensing::Customers::V1::GetUsersResponse.new(
            customer_id: organization.licensed_customer_id,
            users: users,
          )
        end

        sig { params(customer_id: Integer, page_token: String, page_size: Integer).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetUsersResponse, Twirp::Error)) }
        def handle_customer_entity(customer_id, page_token, page_size)
          users = T.let([], T::Array[MonolithTwirp::Licensing::Customers::V1::User])
          next_page_token = ""

          unless customer = Customer.select(:id).find_by(id: customer_id)
            return Twirp::Error.not_found("customer not found")
          end

          if business = Business.find_by(customer_id: customer.id)
            users, next_page_token = get_users_for_business(business, page_token, page_size)
          else
            organizations = customer.organizations.active.where.missing(:business).select(:id, :raw_data).reject { |org| org.deleted? }.to_a
            users, next_page_token = get_users_for_orgs(organizations) if organizations.any?
          end

          MonolithTwirp::Licensing::Customers::V1::GetUsersResponse.new(
            customer_id: customer.id,
            users: users,
            next_page_token: next_page_token,
          )
        end

        sig { params(organizations: T::Array[Organization]).returns([T::Array[MonolithTwirp::Licensing::Customers::V1::User], String]) }
        def get_users_for_orgs(organizations)
          org_memberships_by_user = organizations.each_with_object({}) do |org, result|
            org.member_ids.map do |user_id|
              result[user_id] ||= []
              result[user_id] << T.must(org.id)
            end
            result
          end

          repo_memberships_by_user = get_repo_memberships(organizations.pluck(:id))

          users = build_users_list(org_memberships_by_user, repo_memberships_by_user, {})

          [users, ""]
        end

        sig { params(business: Business, page_token: String, page_size: Integer).returns([T::Array[MonolithTwirp::Licensing::Customers::V1::User], String]) }
        def get_users_for_business(business, page_token, page_size)
          users = []
          cursor = page_token.to_i
          next_cursor = ""

          all_org_ids = business.organizations
            .select(:id, :raw_data) # the deleted attribute is stored in raw_data
            .where("users.id > ?", cursor)
            .order(id: :asc)
            .reject { |org| org.deleted? }
            .pluck(:id)

          is_last_page = all_org_ids.size <= page_size
          page_ids = all_org_ids.first(page_size)

          if page_ids.any?
            org_and_user_ids = business.business_org_abilities(org_ids: page_ids).pluck(:subject_id, :actor_id) || []
            org_memberships_by_user = org_and_user_ids.each_with_object(Hash.new { |h, user_id| h[user_id] = [] }) do |(org_id, user_id), memo|
              memo[user_id] << org_id
            end

            repo_memberships_by_user = get_repo_memberships(page_ids)

            member_ids = org_memberships_by_user.keys | repo_memberships_by_user.keys
            suspended_users = get_suspended_users_for_business(business, member_ids)

            users = build_users_list(org_memberships_by_user, repo_memberships_by_user, suspended_users)

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
            .pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))

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

        sig { params(business: Business, member_ids: T::Array[Integer]).returns(T::Hash[Integer, Time]) }
        def get_suspended_users_for_business(business, member_ids)
          business.suspended_members&.where(id: member_ids)&.pluck(:id, :suspended_at)&.to_h || {}
        end

        sig do
          params(
            org_memberships_by_user: T::Hash[Integer, T::Array[Integer]],
            repo_memberships_by_user: T::Hash[Integer, T::Array[Integer]],
            suspended_users: T::Hash[Integer, Time],
          ).returns(T::Array[MonolithTwirp::Licensing::Customers::V1::User])
        end
        def build_users_list(org_memberships_by_user, repo_memberships_by_user, suspended_users)
          merged = Hash.new { |h, user_id| h[user_id] = MonolithTwirp::Licensing::Customers::V1::User.new(id: user_id) }
          org_memberships_by_user.each do |user_id, org_ids|
            merged[user_id].organization_memberships += org_ids
          end
          repo_memberships_by_user.each do |user_id, repo_ids|
            merged[user_id].collaborating_repositories += repo_ids
          end
          suspended_users.each do |user_id, suspended_at|
            merged[user_id].suspended_at = Google::Protobuf::Timestamp.new(seconds: suspended_at.to_i)
          end
          merged.values
        end
      end
    end
  end
end
