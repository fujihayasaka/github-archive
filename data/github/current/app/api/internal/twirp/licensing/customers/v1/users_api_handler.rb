# typed: true
# frozen_string_literal: true

require "monolith-twirp-licensing-customers"

module Api::Internal::Twirp::Licensing
  module Customers
    module V1
      # Handler for the MonolithTwirp::Licensing::Customers::V1::UsersAPIService
      class UsersAPIHandler < Api::Internal::Twirp::Handler
        include Scientist

        allow_access_for :client, allowed_clients: %w(licensing billing)
        handles_service MonolithTwirp::Licensing::Customers::V1::UsersAPIService

        DEFAULT_ORGS_PAGE_SIZE = 5000
        REPO_MEMBERSHIP_BATCH_SIZE = 500
        MAX_REPOS_PER_PAGE = 250
        MAX_COPILOT_PAGE_SIZE = 10_000
        MAX_TEAM_PAGE_SIZE = 10_000
        # Sentinel that follows the org/repo cursor in the page token once org pagination is
        # exhausted and we begin emitting non-license-consuming members. Format: "u:<user_cursor>".
        NON_LICENSE_CONSUMING_PAGE_TOKEN_PREFIX = "u"

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
            ::Failbot.push "gh.organization.id": entity_id
            return handle_org_entity(entity_id, direct_members_only: req.direct_members_only)
          end

          # Customer requested
          page_size = req.page_size > 0 ? req.page_size : DEFAULT_ORGS_PAGE_SIZE
          ::Failbot.push "gh.billing.customer.id": entity_id
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

          ::Failbot.push "gh.billing.customer.id": customer_id

          payload = MonolithTwirp::Licensing::Customers::V1::Customer.new(customer.to_licensify_customer_payload)
          MonolithTwirp::Licensing::Customers::V1::GetCustomerResponse.new(customer: payload)
        end

        # Public: Implementation of the GetBusinessTeamMembers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::Customers::V1::GetBusinessTeamMembersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Licensing::Customers::V1::GetBusinessTeamMembersResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::Customers::V1::GetBusinessTeamMembersRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetBusinessTeamMembersResponse, Twirp::Error))
        end
        def get_business_team_members(req, env)
          unless business_team_id = id_argument(req.business_team_id)
            return Twirp::Error.invalid_argument("business_team_id is required", argument: "business_team_id")
          end

          business_team = BusinessTeam.find_by(id: business_team_id)

          return Twirp::Error.not_found("business team not found") unless business_team

          ::Failbot.push "gh.business_team.id": business_team_id

          all_member_ids = business_team.member_ids

          if req.page_size > 0
            paginate_team_members_response(
              all_member_ids,
              req.page_token,
              req.page_size,
              MonolithTwirp::Licensing::Customers::V1::GetBusinessTeamMembersResponse,
            )
          else
            MonolithTwirp::Licensing::Customers::V1::GetBusinessTeamMembersResponse.new(user_ids: all_member_ids)
          end
        end

        # Public: Implementation of the GetOrgTeamMembers Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::Customers::V1::GetOrgTeamMembersRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a
        # MonolithTwirp::Licensing::Customers::V1::GetOrgTeamMembersResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::Customers::V1::GetOrgTeamMembersRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetOrgTeamMembersResponse, Twirp::Error))
        end
        def get_org_team_members(req, env)
          unless team_id = id_argument(req.team_id)
            return Twirp::Error.invalid_argument("team_id is required", argument: "team_id")
          end

          team = Team.find_by(id: team_id)

          return Twirp::Error.not_found("team not found") unless team
          return Twirp::Error.not_found("team not found") if team.deleted?

          ::Failbot.push "gh.team.id": team_id

          all_member_ids = team.member_ids

          if req.page_size > 0
            paginate_team_members_response(
              all_member_ids,
              req.page_token,
              req.page_size,
              MonolithTwirp::Licensing::Customers::V1::GetOrgTeamMembersResponse,
            )
          else
            MonolithTwirp::Licensing::Customers::V1::GetOrgTeamMembersResponse.new(user_ids: all_member_ids)
          end
        end

        # Public: Implementation of the GetCopilotSeatedUserIds Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Licensing::Customers::V1::GetCopilotSeatedUserIdsRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a
        # MonolithTwirp::Licensing::Customers::V1::GetCopilotSeatedUserIdsResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Licensing::Customers::V1::GetCopilotSeatedUserIdsRequest,
            env: T::Hash[T.untyped, T.untyped],
          ).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetCopilotSeatedUserIdsResponse, Twirp::Error))
        end
        def get_copilot_seated_user_ids(req, env)
          entity_type = req.entity_type

          if entity_type.blank?
            return Twirp::Error.invalid_argument("entity_type is required", argument: "entity_type")
          end

          unless entity_id = id_argument(req.entity_id)
            return Twirp::Error.invalid_argument("entity_id is required", argument: "entity_id")
          end

          unless %w[Organization Team BusinessTeam].include?(entity_type)
            return Twirp::Error.invalid_argument("unsupported entity_type: #{entity_type}", argument: "entity_type")
          end

          ::Failbot.push "gh.entity.id": entity_id, "gh.entity.type": entity_type

          page_size = req.page_size > 0 ? [req.page_size, MAX_COPILOT_PAGE_SIZE].min : MAX_COPILOT_PAGE_SIZE

          if req.page_token.present?
            begin
              cursor = Integer(req.page_token)
            rescue ArgumentError
              return Twirp::Error.invalid_argument("page_token must be a numeric cursor", argument: "page_token")
            end
          else
            cursor = 0
          end

          case entity_type
          when "Organization"
            copilot_seated_user_ids_for_organization(entity_id, cursor, page_size)
          when "Team"
            copilot_seated_user_ids_for_team(entity_id, cursor, page_size)
          when "BusinessTeam"
            copilot_seated_user_ids_for_business_team(entity_id, cursor, page_size)
          else
            # Unreachable: entity_type is validated above. Satisfies Sorbet exhaustiveness.
            Twirp::Error.invalid_argument("unsupported entity_type: #{entity_type}", argument: "entity_type")
          end
        end

        private

        sig do
          params(
            all_member_ids: T::Array[Integer],
            page_token: String,
            page_size: Integer,
            response_class: T.untyped,
          ).returns(T.untyped)
        end
        def paginate_team_members_response(all_member_ids, page_token, page_size, response_class)
          page_size = [page_size, MAX_TEAM_PAGE_SIZE].min
          if page_token.empty?
            offset = 0
          else
            begin
              offset = Integer(page_token, 10)
            rescue ArgumentError
              return Twirp::Error.invalid_argument("page_token must be a numeric cursor", argument: "page_token")
            end
            if offset < 0
              return Twirp::Error.invalid_argument("page_token must be a non-negative cursor", argument: "page_token")
            end
          end
          page_ids = all_member_ids[offset, page_size] || []

          users = User.where(id: page_ids).select(:id, :suspended_at).map do |user|
            attrs = { id: user.id }
            attrs[:suspended_at] = Google::Protobuf::Timestamp.new(seconds: user.suspended_at.to_i) if user.suspended_at
            MonolithTwirp::Licensing::Customers::V1::User.new(**attrs)
          end

          next_offset = offset + page_size
          next_page_token = next_offset < all_member_ids.size ? next_offset.to_s : ""

          response_class.new(user_ids: page_ids, users: users, next_page_token: next_page_token)
        end

        sig { params(org_id: Integer, cursor: Integer, page_size: Integer).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetCopilotSeatedUserIdsResponse, Twirp::Error)) }
        def copilot_seated_user_ids_for_organization(org_id, cursor, page_size)
          unless organization = Organization.find_by(id: org_id)
            return Twirp::Error.not_found("organization not found")
          end

          unless organization.active?
            return Twirp::Error.not_found("organization deleted")
          end

          # Exclude seats whose assignment has been revoked (access_revoked_at IS NOT NULL),
          # because revoked seats are conceptually inactive even though the rows still exist.
          user_ids = Copilot::Seat
            .for_organization(organization)
            .joins(:seat_assignment)
            .where(copilot_seat_assignments: { access_revoked_at: nil })
            .where("copilot_seats.assigned_user_id > ?", cursor)
            .distinct
            .order(:assigned_user_id)
            .limit(page_size + 1)
            .pluck(:assigned_user_id)

          build_copilot_response(user_ids, page_size)
        end

        sig { params(team_id: Integer, cursor: Integer, page_size: Integer).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetCopilotSeatedUserIdsResponse, Twirp::Error)) }
        def copilot_seated_user_ids_for_team(team_id, cursor, page_size)
          unless team = Team.find_by(id: team_id)
            return Twirp::Error.not_found("team not found")
          end
          return Twirp::Error.not_found("team not found") if team.deleted?

          # member_ids loads all team member IDs into memory, which produces a large IN (...)
          # clause for big teams. An alternative is to paginate seats first and intersect in
          # Ruby, but that can require scanning many seat pages to fill one result page. This
          # endpoint isn't a hot path, so the simpler approach is fine for now.
          member_ids = team.member_ids
          return build_copilot_response([], page_size) if member_ids.empty?

          # Per ADR 024 §3: query any Copilot seat in the org, not just seats attributed to
          # this team. A user in multiple teams only has one seat, arbitrarily attributed to
          # one of them. Querying per-team would miss members whose seat is on another team.
          user_ids = Copilot::Seat
            .for_organization(team.organization)
            .joins(:seat_assignment)
            .where(copilot_seat_assignments: { access_revoked_at: nil })
            .where(assigned_user_id: member_ids)
            .where("copilot_seats.assigned_user_id > ?", cursor)
            .distinct
            .order(:assigned_user_id)
            .limit(page_size + 1)
            .pluck(:assigned_user_id)

          build_copilot_response(user_ids, page_size)
        end

        sig { params(business_team_id: Integer, cursor: Integer, page_size: Integer).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetCopilotSeatedUserIdsResponse, Twirp::Error)) }
        def copilot_seated_user_ids_for_business_team(business_team_id, cursor, page_size)
          unless business_team = BusinessTeam.find_by(id: business_team_id)
            return Twirp::Error.not_found("business team not found")
          end
          return Twirp::Error.not_found("business team not found") if business_team.deleted?

          unless business = business_team.business
            return Twirp::Error.not_found("business not found")
          end

          # member_ids loads all BT member IDs into memory, which produces a large IN (...)
          # clause for big teams. See comment in copilot_seated_user_ids_for_team for rationale.
          member_ids = business_team.member_ids
          return build_copilot_response([], page_size) if member_ids.empty?

          # Query all active seats in the business (org-scoped + business-owned), not just seats
          # in the BT's assigned orgs. This matches ADR 024's broadening approach: same as Team
          # checks "any seat in the org" rather than per-team, BT checks the full business to
          # avoid missing members whose seats are attributed to different assignments.
          # all_active_seats_in_business already filters access_revoked_at: nil.
          user_ids = Copilot::Seat
            .all_active_seats_in_business(business)
            .where(assigned_user_id: member_ids)
            .where("copilot_seats.assigned_user_id > ?", cursor)
            .distinct
            .order(:assigned_user_id)
            .limit(page_size + 1)
            .pluck(:assigned_user_id)

          build_copilot_response(user_ids, page_size)
        end

        sig { params(user_ids: T::Array[Integer], page_size: Integer).returns(MonolithTwirp::Licensing::Customers::V1::GetCopilotSeatedUserIdsResponse) }
        def build_copilot_response(user_ids, page_size)
          if user_ids.size > page_size
            user_ids = user_ids.first(page_size)
            next_page_token = user_ids.last.to_s
          else
            next_page_token = ""
          end

          MonolithTwirp::Licensing::Customers::V1::GetCopilotSeatedUserIdsResponse.new(user_ids: user_ids, next_page_token: next_page_token)
        end

        sig { params(org_id: Integer, direct_members_only: T::Boolean).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetUsersResponse, Twirp::Error)) }
        def handle_org_entity(org_id, direct_members_only: false)
          unless organization = Organization.includes(:business).find_by(id: org_id)
            return Twirp::Error.not_found("organization not found")
          end

          unless organization.active?
            return Twirp::Error.not_found("organization deleted")
          end

          org_memberships_by_user = organization.member_ids(include_indirect_abilities: !direct_members_only).each_with_object({}) do |user_id, result|
            result[user_id] ||= [org_id]
          end

          # When direct_members_only is true, we intentionally skip fetching business team
          # memberships. These are only relevant for indirect members, and callers using this
          # flag (e.g., Copilot org sync) don't need team membership data.
          team_memberships_by_user = if !direct_members_only && organization.business.present?
            get_business_team_memberships(business_id: organization.business&.id, org_ids: [org_id])
          else
            {}
          end

          suspended_users = get_suspended_users(org_memberships_by_user.keys)

          users = build_users_list(org_memberships_by_user, {}, team_memberships_by_user, suspended_users)

          MonolithTwirp::Licensing::Customers::V1::GetUsersResponse.new(
            customer_id: organization.licensed_customer_id,
            users: users,
          )
        end

        sig { params(customer_id: Integer, page_token: String, page_size: Integer).returns(T.any(MonolithTwirp::Licensing::Customers::V1::GetUsersResponse, Twirp::Error)) }
        def handle_customer_entity(customer_id, page_token, page_size)
          GitHub.logger.info({
            message: "Fetching users for customer",
            page_token: page_token,
            page_size: page_size,
            "gh.billing.customer.id": customer_id,
            "code.namespace": self.class.name,
            "code.method": __method__.to_s,
          })

          users = T.let([], T::Array[MonolithTwirp::Licensing::Customers::V1::User])
          next_page_token = ""

          unless customer = Customer.select(:id).find_by(id: customer_id)
            return Twirp::Error.not_found("customer not found")
          end

          if business = Business.find_by(customer_id: customer.id)
            users, next_page_token = get_users_for_business(business, page_token, page_size)
          else
            organizations = customer.organizations.active.where.missing(:business).select(:id, :raw_data).reject { |org| org.deleted? }.to_a
            users, next_page_token = get_users_for_orgs(organizations, customer) if organizations.any?
          end

          MonolithTwirp::Licensing::Customers::V1::GetUsersResponse.new(
            customer_id: customer.id,
            users: users,
            next_page_token: next_page_token,
          )
        end

        sig { params(organizations: T::Array[Organization], customer: Customer).returns([T::Array[MonolithTwirp::Licensing::Customers::V1::User], String]) }
        def get_users_for_orgs(organizations, customer)
          org_memberships_by_user = organizations.each_with_object({}) do |org, result|
            org.member_ids.map do |user_id|
              result[user_id] ||= []
              result[user_id] << T.must(org.id)
            end
            result
          end

          repo_memberships_by_user = get_repo_memberships(organizations.pluck(:id), customer)

          # No business is present on this path (Customer.organizations.where.missing(:business)),
          # so SCIM-managed suspension is not applicable; only staff suspension can apply.
          suspended_users = get_suspended_users(org_memberships_by_user.keys)

          users = build_users_list(org_memberships_by_user, repo_memberships_by_user, {}, suspended_users)

          [users, ""]
        end

        # Paginated version that handles large orgs with many repos by using a compound page token.
        # Page token format:
        #   "" (empty)                  - start from the beginning
        #   "<org_cursor>"              - continue org pagination starting from this org id
        #   "<org_cursor>:<repo_cursor>"- continue paginating repos within an org
        #   "u:<user_cursor>"           - org pagination complete; paginate non-license-consuming members
        sig { params(business: Business, page_token: String, page_size: Integer).returns([T::Array[MonolithTwirp::Licensing::Customers::V1::User], String]) }
        def get_users_for_business(business, page_token, page_size)
          if non_license_consuming_page_token?(page_token)
            return get_non_license_consuming_users_for_business(business, page_token, page_size)
          end

          users = []
          next_cursor = ""
          org_cursor, repo_cursor = parse_page_token(page_token)

          all_org_ids = business.organizations
            .select(:id, :raw_data) # the deleted attribute is stored in raw_data
            .where("users.id >= ?", org_cursor) # organizations are users
            .order(id: :asc)
            .limit(page_size + 1)
            .reject { |org| org.deleted? }
            .pluck(:id)

          return get_non_license_consuming_users_for_business(business, build_non_license_consuming_page_token(0), page_size) if all_org_ids.empty?

          # If we have a repo_cursor > 0, we're paginating by repo within the current org
          is_continuing_within_org = repo_cursor > 0 && org_cursor > 0
          if is_continuing_within_org
            page_org_ids = all_org_ids.first(1)
          else
            page_org_ids = all_org_ids.first(page_size)
          end

          if page_org_ids.any?
            # Only fetch org/team memberships on the first page for an org (when repo_cursor is 0)
            # This avoids returning duplicate membership data when paginating through repos
            if is_continuing_within_org
              org_memberships_by_user = {}
              team_memberships_by_user = {}
            else
              org_and_user_ids = business.business_org_abilities(org_ids: page_org_ids, include_indirect_abilities: false).pluck(:subject_id, :actor_id).to_a || []
              org_memberships_by_user = org_and_user_ids.each_with_object(Hash.new { |h, user_id| h[user_id] = [] }) do |(org_id, user_id), memo|
                memo[user_id] << org_id
              end
              team_memberships_by_user = get_business_team_memberships(business_id: business.id, org_ids: page_org_ids)
            end

            repo_memberships_by_user, next_repo_cursor, next_org_cursor = get_repo_memberships_paginated(page_org_ids, business.customer, repo_cursor)

            # Only fetch suspended status for users we're returning data for
            # On first page, include all members; on subsequent pages, only repo collaborators
            if is_continuing_within_org
              member_ids = repo_memberships_by_user.keys
            else
              member_ids = org_memberships_by_user.keys | repo_memberships_by_user.keys | team_memberships_by_user.keys
            end
            suspended_users = get_suspended_users(member_ids)

            users = build_users_list(org_memberships_by_user, repo_memberships_by_user, team_memberships_by_user, suspended_users)

            # Determine next page token
            if next_repo_cursor > 0 && next_org_cursor > 0
              # More repos to process within the current org
              next_cursor = "#{next_org_cursor}:#{next_repo_cursor}"
            elsif all_org_ids.size > page_org_ids.size
              # There are more orgs to process, move cursor to next org after the current page
              next_cursor = all_org_ids[page_org_ids.size].to_s
            else
              # Org pagination is complete; advance to the non-license-consuming phase on the next call.
              next_cursor = build_non_license_consuming_page_token(0)
            end
          end

          [users, next_cursor]
        end

        sig { params(page_token: String).returns(T::Boolean) }
        def non_license_consuming_page_token?(page_token)
          page_token.start_with?("#{NON_LICENSE_CONSUMING_PAGE_TOKEN_PREFIX}:")
        end

        sig { params(user_cursor: Integer).returns(String) }
        def build_non_license_consuming_page_token(user_cursor)
          "#{NON_LICENSE_CONSUMING_PAGE_TOKEN_PREFIX}:#{user_cursor}"
        end

        sig { params(page_token: String).returns(Integer) }
        def parse_non_license_consuming_page_token(page_token)
          parts = page_token.split(":", 2)
          parts[1].to_i
        end

        # Emits business members that are not consuming a license, paginated by `user_id`. A user
        # is considered non-license-consuming when their `business_roles_bitfield` is `0` or
        # contains only some combination of `owner`, `billing_manager`, and `emu_admin`.
        # License-consuming roles (`member`, `outside_collaborator`, `guest_collaborator`,
        # `server_member`) are excluded, as are users with the `server_admin` or `suspended` role
        # bit. These users are returned with empty organization, repository, and business team
        # memberships; only `suspended_at` is populated when applicable (via the standard
        # suspension lookup on `User.suspended_at` / SCIM).
        sig { params(business: Business, page_token: String, page_size: Integer).returns([T::Array[MonolithTwirp::Licensing::Customers::V1::User], String]) }
        def get_non_license_consuming_users_for_business(business, page_token, page_size)
          user_cursor = parse_non_license_consuming_page_token(page_token)

          # `no_roles` matches BusinessUserAccount rows whose `business_roles_bitfield` does not
          # have any of the excluded bits set. This returns users whose bitfield is `0` as well as
          # users whose only set bits are within {owner, billing_manager, emu_admin} — all of which
          # are non-license-consuming roles.
          user_ids = business.user_accounts
            .no_roles([:member, :outside_collaborator, :guest_collaborator, :server_member, :server_admin, :suspended])
            .where("business_user_accounts.user_id > ?", user_cursor)
            .order(:user_id)
            .limit(page_size + 1)
            .pluck(:user_id)

          has_more = user_ids.size > page_size
          page_user_ids = user_ids.first(page_size)

          next_cursor = has_more && page_user_ids.any? ? build_non_license_consuming_page_token(T.must(page_user_ids.last)) : ""

          if page_user_ids.empty?
            return [[], next_cursor]
          end

          suspended_users = get_suspended_users(page_user_ids)

          # Emit a User entry for every non-license-consuming member, even those without a
          # suspension, so callers can distinguish "user not in customer" from "user in customer
          # with no memberships". Memberships are intentionally empty.
          users = page_user_ids.map do |user_id|
            user = MonolithTwirp::Licensing::Customers::V1::User.new(id: user_id)
            if (suspended_at = suspended_users[user_id])
              user.suspended_at = Google::Protobuf::Timestamp.new(seconds: suspended_at.to_i)
            end
            user
          end

          [users, next_cursor]
        end

        sig { params(org_ids: T::Array[Integer], customer: T.nilable(Customer)).returns(T::Hash[Integer, T::Array[Integer]]) }
        def get_repo_memberships(org_ids, customer)
          GitHub.logger.info({
            message: "Fetching repository memberships for org ids",
            org_ids_count: org_ids.size,
            "code.namespace": self.class.name,
            "code.method": __method__.to_s,
            "gh.billing.customer.id": customer&.id,
          })

          advisory_workspace_repo_ids = RepositoryAdvisory
            .where(owner_id: org_ids)
            .where.not(workspace_repository_id: nil)
            .pluck(:workspace_repository_id)

          repo_ids = Repository.active.private_scope.not_forks
            .where(organization_id: org_ids)
            .where.not(id: advisory_workspace_repo_ids)
            .pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id"))

          GitHub.logger.info({
            message: "Fetched repository IDs for org ids",
            repo_ids_count: repo_ids.size,
            "code.namespace": self.class.name,
            "code.method": __method__.to_s,
          })

          user_and_repo_id_pairs = fetch_user_and_repo_id_pairs(repo_ids)

          GitHub.logger.info({
            message: "Fetched user and repository ID pairs for org ids",
            user_and_repo_pairs_count: user_and_repo_id_pairs.size,
            "code.namespace": self.class.name,
            "code.method": __method__.to_s,
            "gh.billing.customer.id": customer&.id,
          })

          result_hash = user_and_repo_id_pairs.group_by(&:first).transform_values do |pairs|
            pairs.map(&:last)
          end

          GitHub.logger.info({
            message: "Transformed user and repository ID pairs into a hash",
            result_hash_size: result_hash.size,
            "code.namespace": self.class.name,
            "code.method": __method__.to_s,
            "gh.billing.customer.id": customer&.id,
          })

          result_hash
        end

        sig { params(repo_ids: T::Array[Integer]).returns(T::Array[[Integer, Integer]]) }
        def fetch_user_and_repo_id_pairs(repo_ids)
          ::Ability.from("abilities FORCE INDEX(subject_and_actor_and_priority_and_action)").batched_scope(:subject_id, values: repo_ids) do |scope|
            scope
              .where(subject_type: "Repository", actor_type: "User", priority: Ability.priorities[:direct])
              .distinct
          end.pluck(:actor_id, :subject_id)
        end

        # Parse a compound page token into org_cursor and repo_cursor
        # Format: "org_cursor" or "org_cursor:repo_cursor"
        sig { params(page_token: String).returns([Integer, Integer]) }
        def parse_page_token(page_token)
          return [0, 0] if page_token.blank?

          parts = page_token.split(":")
          org_cursor = parts[0].to_i
          repo_cursor = parts[1].to_i
          [org_cursor, repo_cursor]
        end

        # Fetch repo memberships with pagination by repo
        # Returns [memberships_hash, next_repo_cursor, next_org_cursor]
        sig { params(org_ids: T::Array[Integer], customer: T.nilable(Customer), repo_cursor: Integer).returns([T::Hash[Integer, T::Array[Integer]], Integer, Integer]) }
        def get_repo_memberships_paginated(org_ids, customer, repo_cursor)
          GitHub.logger.info({
            message: "Fetching paginated repository memberships for org ids",
            org_ids_count: org_ids.size,
            repo_cursor: repo_cursor,
            "code.namespace": self.class.name,
            "code.method": __method__.to_s,
            "gh.billing.customer.id": customer&.id,
          })

          return [{}, 0, 0] if org_ids.empty?

          advisory_workspace_repo_ids = RepositoryAdvisory
            .where(owner_id: org_ids)
            .where.not(workspace_repository_id: nil)
            .pluck(:workspace_repository_id)

          repo_query = Repository.active.private_scope.not_forks
            .where(organization_id: org_ids)
            .where.not(id: advisory_workspace_repo_ids)
            .where("repositories.id > ?", repo_cursor)
            .order(:organization_id, :id)
            .limit(MAX_REPOS_PER_PAGE + 1)

          repo_results = repo_query.pluck(Arel.sql("/*vt+ IGNORE_MAX_MEMORY_ROWS=1 */ id, organization_id"))

          has_more_repos = repo_results.size > MAX_REPOS_PER_PAGE

          page_results = repo_results.first(MAX_REPOS_PER_PAGE)
          repo_ids = page_results.map(&:first)

          next_repo_cursor = has_more_repos ? page_results.last.first : 0
          next_org_cursor = has_more_repos ? page_results.last.last : 0

          GitHub.logger.info({
            message: "Fetched paginated repository IDs for org ids",
            repo_ids_count: repo_ids.size,
            has_more_repos: has_more_repos,
            next_repo_cursor: next_repo_cursor,
            next_org_cursor: next_org_cursor,
            "code.namespace": self.class.name,
            "code.method": __method__.to_s,
            "gh.billing.customer.id": customer&.id,
          })

          return [{}, 0, 0] if repo_ids.empty?

          user_and_repo_id_pairs = fetch_user_and_repo_id_pairs(repo_ids)

          GitHub.logger.info({
            message: "Fetched paginated user and repository ID pairs",
            user_and_repo_pairs_count: user_and_repo_id_pairs.size,
            "code.namespace": self.class.name,
            "code.method": __method__.to_s,
            "gh.billing.customer.id": customer&.id,
          })

          result_hash = user_and_repo_id_pairs.group_by(&:first).transform_values do |pairs|
            pairs.map(&:last)
          end

          [result_hash, next_repo_cursor, next_org_cursor]
        end

        sig { params(business_id: T.nilable(Integer), org_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[Integer]]) }
        def get_business_team_memberships(business_id:, org_ids:)
          return {} unless business_id
          team_ids = Orgs.domain.teams.all_business_team_ids_for(business_id: business_id, organization_ids: org_ids)
          return {} if team_ids.empty?

          Orgs.domain.teams.team_ids_by_user_id_for(team_ids)
        end

        # Returns {user_id => suspended_at} for the given member_ids. A single
        # `User.suspended_at IS NOT NULL` query covers both staff- and SCIM-driven suspensions
        # (the SCIM provisioner calls `user.suspend` as part of deprovisioning).
        sig do
          params(
            member_ids: T::Array[Integer],
          ).returns(T::Hash[Integer, Time])
        end
        def get_suspended_users(member_ids)
          return {} if member_ids.empty?

          User.where.not(suspended_at: nil).batched_scope(:id, values: member_ids).pluck(:id, :suspended_at).to_h
        end

        sig do
          params(
            org_memberships_by_user: T::Hash[Integer, T::Array[Integer]],
            repo_memberships_by_user: T::Hash[Integer, T::Array[Integer]],
            business_team_memberships_by_user: T::Hash[Integer, T::Array[Integer]],
            suspended_users: T::Hash[Integer, Time],
          ).returns(T::Array[MonolithTwirp::Licensing::Customers::V1::User])
        end
        def build_users_list(org_memberships_by_user, repo_memberships_by_user, business_team_memberships_by_user, suspended_users)
          merged = Hash.new { |h, user_id| h[user_id] = MonolithTwirp::Licensing::Customers::V1::User.new(id: user_id) }
          org_memberships_by_user.each do |user_id, org_ids|
            merged[user_id].organization_memberships += org_ids
          end
          repo_memberships_by_user.each do |user_id, repo_ids|
            merged[user_id].collaborating_repositories += repo_ids
          end
          business_team_memberships_by_user.each do |user_id, team_ids|
            merged[user_id].business_team_memberships += team_ids
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
