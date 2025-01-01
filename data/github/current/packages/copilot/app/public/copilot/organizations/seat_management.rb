# typed: strict
# frozen_string_literal: true

# This module encapsulates all of the SeatAssignment logic
#
# A seat can be assigned to one of the VALID_ASSIGNABLE_TYPES (User, OrganizationInvitation, Team or Organization)
module Copilot
  module Organizations
    module SeatManagement

      extend T::Helpers

      include Copilot::Helpers
      include Copilot::Organizations::Signatures
      include GitHub::Memoizer

      abstract!

      VALID_SORT_VALUES = T.let(%i[sortable_name last_activity_at pending_cancellation_date nil_sort].freeze, T::Array[Symbol])
      VALID_FILTER_VALUES = T.let(%i[all users teams organizationinvitations].freeze, T::Array[Symbol])

      # This is the User seat count threshold over which we do not show or query for last_activity_at so that
      # the seat management page for orgs with a large number of User seats does not time out
      ACTIVITY_DISPLAY_THRESHOLD = T.let(10_000, Integer)

      sig do
        params(
          query: T.nilable(String),
          type: Symbol,
          sort: Symbol,
          direction: Symbol
        ).returns(T::Array[Copilot::Organizations::SeatManagement::Detail])
      end
      def seat_assignments(query: "", type: :all, sort: :last_activity_at, direction: :desc)
        type = :all unless VALID_FILTER_VALUES.include?(type)
        sort = :last_activity_at unless VALID_SORT_VALUES.include?(sort)

        load_details(query, type, sort, direction)
      end

      ## This is only called for Allow All or Disabled
      sig do
        params(
          query: T.nilable(String),
          type: Symbol,
          sort: Symbol,
          direction: Symbol
        ).returns(T::Array[Copilot::Organizations::SeatManagement::Detail])
      end
      def all_org_seat_assignments(query: "", type: :all, sort: :last_activity_at, direction: :desc)
        type = :all unless VALID_FILTER_VALUES.include?(type)
        sort = :last_activity_at unless VALID_SORT_VALUES.include?(sort)

        return [] if type == :teams || type == :organizationinvitations

        # this should only be called for Organization Level SeatAssignments
        assignment = Copilot::SeatAssignment.organization_seat_assignment(organization_object)
        revoked_assignments = Copilot::SeatAssignment.where(organization: organization_object).where.not(access_revoked_at: nil).index_by(&:assignable_id)
        user_ids = Copilot::Seat.for_organization(organization_object).pluck(:assigned_user_id)

        users = []
        if query == ""
          users = ::User.where(id: user_ids).includes(:profile)
        else
          users = ::User.where(id: user_ids).where(["users.login LIKE :query", { query: "%#{query}%" }]).includes(:profile)
        end

        # don't do this query or show activity if the org has a ton of members
        usage_data = display_activity?(user_ids.size) ? Copilot::AggregateUsageDetail.where("user_id IN (?)", users.map(&:id)).group(:user_id).select("MAX(updated_at) as updated_at, user_id").index_by(&:user_id) : {}

        all_users = []

        users.each do |user|
          revoked_assignment = revoked_assignments[user.id]
          assignment_for_detail = if revoked_assignment
            revoked_assignment
          elsif assignment
            assignment
          else
            Copilot::SeatAssignment.new(assignable_type: "Organization", assignable_id: organization_object.id)
          end

          pending_cancellation_date = assignment_for_detail.pending_cancellation_date

          activity = usage_data[user.id]
          last_activity_at = activity ? activity.updated_at : nil

          all_users << Copilot::Organizations::SeatManagement::Detail.new(
            organization: organization_object,
            # Because we are looping through users that belong to an organization-level seat assignment,
            # we need to provide a dummy seat assignment to the SeatDetail object.
            # We fake an organization assignment because we want to trigger the organization payload builder.
            # This builder inherits from the user payload builder, but overwrites the `assignable` property to point
            # to the assigned user specified below in the constructor; this allows a user to be properly serialized
            # from the SeatDetail object.
            seat_assignment: assignment_for_detail,
            assignable: assignment_for_detail.access_revoked? ? user : organization_object, # organization
            pending_cancellation_date: pending_cancellation_date,
            last_activity_at: last_activity_at, # don't show activity if there are too many org members
            assigned_user: user, #it's real, casey!
            access_revoked_at: assignment_for_detail.access_revoked_at,
          )
        end

        # Process revoked assignments for destroyed users
        processed_user_ids = users.map(&:id).to_set
        revoked_assignments.each do |user_id, revoked_assignment|
          # Skip if we already processed this user
          next if processed_user_ids.include?(user_id)

          # Skip if the assignment is not for a User type
          next unless revoked_assignment.assignable_type == "User"

          # For destroyed users, we can't get the user object, so we create a detail
          # with minimal information from the revoked assignment
          all_users << Copilot::Organizations::SeatManagement::Detail.new(
            organization: organization_object,
            seat_assignment: revoked_assignment,
            assignable: nil, # User has been destroyed
            pending_cancellation_date: revoked_assignment.pending_cancellation_date,
            last_activity_at: nil, # No activity data for destroyed users
            access_revoked_at: revoked_assignment.access_revoked_at,
          )
        end

        all_users = all_users.sort_by do |detail|
          if sort == :sortable_name
            if (detail.assigned_user.profile&.name).present?
              detail.assigned_user.profile.name.downcase
            else
              detail.assigned_user&.login&.downcase || ""
            end
          else
            detail.last_activity_at.to_i
          end
        end
        all_users = all_users.reverse if direction == :desc
        all_users
      end

      # This is the only way to assign - it accepts Assignables or a string for an email
      # We didn't add String to the type alias above because the Emails must be looked up and converted to Users or Invitations
      # Everything downstream of this method expects Assignables
      sig { params(assignables: T::Array[T.any(String, OrganizationAssignable)], assigning_user: ::User).returns(GitHub::Result) }
      def assign(assignables, assigning_user)
        GitHub::Result.new do
          assignables.map do |assignable|
            if assignable.is_a?(String)
              email_address = assignable.to_s
              # this means we have an email address, so we call to Assigner#assign_email_address
              result = assigner.assign_email_address(email_address, assigning_user)

              Kernel.raise result.error unless result.ok?
              result.value!
            else
              result = assigner.assign(assignable, assigning_user)

              Kernel.raise result.error unless result.ok?
              result.value!
            end
          end
        end
      end

      # This is the only way to unassign - it accepts Assignables or a string for an email
      # We didn't add String to the type alias above because the Emails must be looked up and converted to Users or Invitations
      # Everything downstream of this method expects Assignables
      sig { params(assignables: T::Array[T.any(String, OrganizationAssignable)], unassigning_user: ::User).returns(GitHub::Result) }
      def unassign(assignables, unassigning_user)
        GitHub::Result.new do
          assignables.map do |assignable|
            if assignable.is_a?(String)
              email_address = assignable.to_s
              # this means we have an email address, so we call to Invitations#assign_email_address
              result = assigner.unassign_email_address(email_address, unassigning_user)

              Kernel.raise result.error unless result.ok?
              result.value!
            else
              result = assigner.unassign(assignable, unassigning_user)

              Kernel.raise result.error unless result.ok?
              result.value!
            end
          end
        end
      end

      sig { returns(Copilot::SeatManagement::Assigner) }
      def assigner
        Copilot::SeatManagement::Assigner.new(organization_object)
      end

      sig { returns(Copilot::Organizations::SeatManagement::SeatBreakdown) }
      def seat_breakdown
        Copilot::Organizations::SeatManagement::SeatBreakdown.new(organization_object)
      end

      sig { override.returns(T::Boolean) }
      def can_emit_usage?
        return false if copilot_for_business_free?
        return false if on_free_trial?
        return false unless has_copilot_for_business?

        true
      end

      sig { returns(Copilot::Types::CopilotLicenseIdentifiers) }
      def all_copilot_seats_and_assignments_by_type_and_identifier
        user_ids = Copilot::Seat.for_organization(organization_object).pluck(:assigned_user_id)
        team_ids = Copilot::SeatAssignment.where(organization: organization_object, assignable_type: "Team").pluck(:assignable_id)

        seat_assignment_org_invite_ids = Copilot::SeatAssignment.where(organization: organization_object, assignable_type: "OrganizationInvitation").pluck(:assignable_id)
        invite_user_ids, invite_emails = OrganizationInvitation.where(id: seat_assignment_org_invite_ids).pluck(:invitee_id, :email).transpose

        {
          user_ids: user_ids,
          team_ids: team_ids,
          invite_user_ids: invite_user_ids&.compact || [],
          invite_emails: invite_emails&.compact || []
        }
      end

      sig { params(user_seat_count: Integer).returns(T::Boolean) }
      def display_activity?(user_seat_count)
        return true unless organization_object.feature_enabled?(:copilot_seats_table_for_large_orgs)
        user_seat_count < ACTIVITY_DISPLAY_THRESHOLD
      end

      private

      sig { params(query: T.nilable(String), type: Symbol, sort: Symbol, direction: Symbol).returns(T::Array[Copilot::Organizations::SeatManagement::Detail]) }
      def load_details(query, type, sort, direction)
        assignments = Copilot::SeatAssignment
          .includes(:seats)
          .includes(:assignable)
          .where(organization: organization_object)
          .select(:id, :assignable_type, :assignable_id, :pending_cancellation_date, :access_revoked_at)

        assignments = assignments.where(assignable_type: type.to_s.classify) unless type == :all

        # Handles the case when an admin is moving from disabled to enabled for selected members
        # AND the admin indicates they want to start from scratch. Previously, we were not showing
        # seats related to the org-level SeatAssigment; now, we will!
        if has_single_org_seat_assignment?(assignments)
          return copilot_org.all_org_seat_assignments(query: query, type: type, sort: sort, direction: direction)
        end

        user_ids, team_ids = assignments.reduce([[], []]) do |(user_ids, team_ids), seat_assignment|
          case seat_assignment.assignable_type
          when "User"
            user_ids << seat_assignment.assignable_id
          when "Team"
            next [user_ids, team_ids] if seat_assignment.assignable.nil?
            team_ids << seat_assignment.assignable_id
          end
          [user_ids, team_ids]
        end

        # we need to filter out assignments where org invites have been deleted
        all_invitation_assignments = assignments.filter { |seat_assignment| seat_assignment.assignable_type == "OrganizationInvitation" && seat_assignment.assignable.present? }
        invitation_ids = all_invitation_assignments.map do |seat_assignment|
          # don't include invitation ids for expired invitations unless there is no unexpired invitation for the same user/email
          seat_assignment.assignable_id unless seat_assignment.assignable&.expired? && other_pending_invite_exists?(seat_assignment.assignable, all_invitation_assignments)
        end.compact

        org_assignments = assignments.filter { |seat_assignment| seat_assignment.assignable_type == "Organization" }
        org_seat_user_ids = org_assignments.flat_map do |assignment|
          assignment.seats.map(&:assigned_user_id).uniq
        end - user_ids

        assignables = {
          "User" => ::User.where(id: user_ids + org_seat_user_ids).index_by(&:id),
          "Team" => ::Team.where(id: team_ids).index_by(&:id),
          "OrganizationInvitation" => ::OrganizationInvitation.where(id: invitation_ids).index_by(&:id),
          "Organization" => { organization_object.id => organization_object }
        }

        # build a list of ids of all members of all teams assigned and/or all individual users assigned
        # we only really need team member IDs to check if an individual user is part of a team later
        all_team_member_ids = []
        assigned_individual_ids = []

        assignments.map do |seat_assignment|
          assignable = (assignables[seat_assignment.assignable_type] || {})[seat_assignment.assignable_id]

          if seat_assignment.assignable_type == "User"
            # Use the assignable_id because the assignable may be nil, if the user was deleted.
            assigned_individual_ids << seat_assignment.assignable_id
          elsif seat_assignment.assignable_type == "Team"
            next if assignable.nil?
            all_team_member_ids.concat(assignable.member_ids)
          end
        end

        # using user_ids to determine this instead of assigned_individual_ids
        # because we already skip displaying activity for teams
        display_activity = display_activity?(user_ids.size)

        if display_activity
          # We're only getting AggregateUsageDetails for individual users here, because we don't display it for
          # Team seat assignments. We're also just not going to do this query if we have a large number of users.

          # The regular ordered list is most performant when we're querying for team seat assignments
          # that could have thousands of members, but we want to also maintain a copy that's indexed by
          # user id (so that orgs with thousands of user seat assignments don't hit a massive n^2 and time out)
          last_activity_for_users = Copilot::AggregateUsageDetail.where(user_id: assigned_individual_ids)
            .order(updated_at: :desc)
            .pluck(:user_id, :updated_at)
          last_activity_at_by_id = last_activity_for_users.group_by(&:first)
        else
          last_activity_at_by_id = {}
        end

        detail_results = assignments.map do |seat_assignment|
          assignable = (assignables[seat_assignment.assignable_type] || {})[seat_assignment.assignable_id]

          # don't display an individual's seat assignment if it's pending cancellation and the user is a member of a team
          # If revokable access is enabled, it is likely the seat assignment is revoked, and we will want to show it.
          if seat_assignment.pending_cancellation? && seat_assignment.assignable_type == "User"
            # If the assignment is revoked, we want to check if they are a member of a team
            # and if so, show the assignment. Otherwise, hide it.
            next nil if all_team_member_ids.include?(seat_assignment.assignable_id) && !seat_assignment.access_revoked?
          end

          # Don't proceed if the team has been destroyed.
          if seat_assignment.assignable_type == "Team" && assignable.nil?
            next nil
          end

          # Don't proceed if the org invite has been destroyed.
          if seat_assignment.assignable_type == "OrganizationInvitation"
            next nil if assignable.nil?
          end

          # We don't need to do other predicate checks if we know the type is an Organization
          if seat_assignment.assignable_type == "Organization"
            next org_seat_user_ids.map do |user_id|
              Copilot::Organizations::SeatManagement::Detail.new(
                organization: organization_object,
                seat_assignment: seat_assignment,
                assignable: assignables["User"][user_id],
                pending_cancellation_date: seat_assignment.pending_cancellation_date,
                last_activity_at: nil,
                assigned_user: assignables["User"][user_id],
              )
            end
          end

          # we only care about activity for User seats we're displaying, not Team
          # and let's not even do the lookup if there are too many users
          activity = nil
          if display_activity && seat_assignment.assignable_type == "User"
            activity = last_activity_at_by_id[seat_assignment.assignable_id]&.first || nil
          end

          Copilot::Organizations::SeatManagement::Detail.new(
            organization: organization_object,
            seat_assignment: seat_assignment,
            assignable: assignable,
            pending_cancellation_date: seat_assignment.pending_cancellation_date,
            last_activity_at: activity.present? ? activity[1] : nil,
            access_revoked_at: seat_assignment.access_revoked_at,
          )
        end.flatten.compact

        detail_results = detail_results.select { |result| result.sortable_name.downcase.include?(query.downcase) } if query.present?
        detail_results = sorter(detail_results, sort)
        detail_results = detail_results.reverse if direction == :desc
        detail_results
      end

      sig { params(assignments: ActiveRecord::Relation).returns(T::Boolean) }
      def has_single_org_seat_assignment?(assignments)
        assignments.size == 1 && copilot_org.seat_management_enabled_for_selected? && assignments.first&.assignable_type == "Organization"
      end

      sig { returns(Copilot::Organization) }
      memoize def copilot_org
        Copilot::Organization.new(organization_object)
      end

      sig { params(details: T::Array[Copilot::Organizations::SeatManagement::Detail], sort: Symbol).returns(T::Array[Copilot::Organizations::SeatManagement::Detail]) }
      def sorter(details, sort)
        # If there are pending cancelled users, and the page is loading for the first time, we need to show
        # all pending cancelled users first.
        #
        # To detect an initial page load, we look to see if sort is nil.
        #
        # If sort is any value other than pending cancelled,
        # we will sort by that value, even if there are pending cancellations.
        #
        sort_cancelled_default = has_pending_cancellations?(details) && sort == :nil_sort
        if sort == :pending_cancellation_date || sort_cancelled_default
          details.select(&:pending_cancellation_date).sort_by { |detail| detail.send(:pending_cancellation_date) } + details.reject(&:pending_cancellation_date)
        else
          sort = :last_activity_at if sort == :nil_sort
          details.sort_by { |detail| detail.send(sort) }
        end
      end

      sig { params(details: T::Array[Copilot::Organizations::SeatManagement::Detail]).returns(T::Boolean) }
      def has_pending_cancellations?(details)
        details.any? { |detail| !detail.pending_cancellation_date.nil? }
      end

      sig { params(expired_invitation: ::OrganizationInvitation, all_invitation_assignments: T::Array[Copilot::SeatAssignment]).returns(T.nilable(T::Boolean)) }
      def other_pending_invite_exists?(expired_invitation, all_invitation_assignments)
        all_invitation_assignments.any? do |invitation_assignment|
          invitation_assignment.assignable.email == expired_invitation.email && !invitation_assignment.assignable.expired?
        end
      end
    end
  end
end
