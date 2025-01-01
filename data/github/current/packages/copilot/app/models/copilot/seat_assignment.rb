# typed: strict
# frozen_string_literal: true

module Copilot
  class SeatAssignment < ApplicationRecord::Copilot
    include ::Instrumentation::Model
    include Copilot::Helpers
    include GitHub::Memoizer

    VALID_ASSIGNABLE_TYPES = T.let(%w[User OrganizationInvitation EnterpriseTeam Team Organization].freeze, T::Array[String])

    self.table_name = "copilot_seat_assignments"
    self.strict_loading_by_default = true

    belongs_to :assignable, polymorphic: true, strict_loading: false
    belongs_to :organization, class_name: "::Organization", strict_loading: false
    belongs_to :owner, polymorphic: true, strict_loading: false

    # rubocop:todo Rails/InverseOf
    belongs_to :assigning_user, class_name: "::User", foreign_key: :assigning_user_id, strict_loading: false
    has_many :seats, class_name: "Copilot::Seat", foreign_key: :copilot_seat_assignment_id, strict_loading: false,
      after_remove: :destroy_when_empty
    # rubocop:enable Rails/InverseOf

    before_validation :set_owner_type

    validates :assignable, presence: true
    validates :assignable_id, uniqueness: { scope: [:organization, :assignable_type] }
    validates :assignable_id, uniqueness: { scope: [:owner_id, :owner_type, :assignable_type] }
    validates :assigning_user, presence: true
    validates :assignable_type, inclusion: { in: VALID_ASSIGNABLE_TYPES }

    validate :assignable_belongs_to_owner
    validate :owner_must_be_correct_type
    validate :assigning_user_can_assign
    validate :emus_cannot_be_invited
    validate :assignable_not_suspended
    validate :owner_not_suspended

    after_initialize :make_sorbet_happy, unless: :persisted?

    sig { returns(T.nilable(T::Boolean)) }
    attr_accessor :skip_delayed_converter_job

    after_commit :delayed_converter_job, on: :create, unless: :skip_delayed_converter_job
    after_commit :auth_and_capture_job, on: :create
    after_commit :instrument_create, on: :create
    after_commit :instrument_update, on: :update
    after_commit :instrument_destroy, on: :destroy

    scope :for_organization, ->(organization) { organization.present? ? for_organization_id(organization.id) : none }
    scope :for_organization_id, ->(organization_id) do
      where(
        owner_type: "Organization",
        owner_id: organization_id,
      ).or(
        self.where(
          organization_id: organization_id,
        )
      )
    end
    scope :for_enterprise_team_id, -> (team_id) { where(assignable_type: "EnterpriseTeam", assignable_id: team_id) }
    scope :for_enterprise_team, -> (team) { where(owner: team.business, assignable: team) }
    scope :for_owner, ->(owner) { where(owner_id: owner.id, owner_type: owner.class.name) }

    scope :organization_assignments, -> { where(assignable_type: "Organization") }
    scope :pending_cancellation_today, -> { where("pending_cancellation_date < NOW()") }
    scope :pending_cancellation, -> { where.not(pending_cancellation_date: nil) }

    scope :team_assignments, -> (organization) { for_owner(organization).where(assignable_type: "Team") }
    scope :enterprise_team_assignments, -> (business) { for_owner(business).where(assignable_type: "EnterpriseTeam") }

    sig { void }
    def set_owner_type
      if owner.present?
        self.owner_type = owner.class.name
      else
        # default to organization
        self.owner_type = "Organization"
      end
    end

    sig { void }
    def emus_cannot_be_invited
      return unless symbolized_assignable_type == :ORGANIZATION_INVITATION

      errors.add(:assignable_type, "cannot be an invitation") if T.cast(owner, Copilot::Owner).enterprise_managed_user_enabled?
    end

    sig { params(team: ::EnterpriseTeam).returns(Copilot::SeatAssignment) }
    def self.create_for_enterprise_team!(team)
      create!(
        owner: T.must(team.business),
        assignable: team,
        assigning_user: T.must(team.business).owners.first,
      )
    rescue ActiveRecord::ActiveRecordError => ex
      GitHub.logger.error(
        ex,
        "gh.business.id" => team.business_id,
        "gh.enterprise_team.id" => team.id
      )
    end

    sig { void }
    def force_destroy!
      GitHub.logger.info(
        "Forcing destroy on SeatAssignment",
        "gh.copilot.seat_assignment.id" => id,
        "gh.copilot.seat_assignment.assignable_type" => assignable_type,
      )
      # this is a nuclear destroy (for EnterpriseTeams mostly)
      # it deletes all of the Seats and then deletes the SeatAssignment and calls instrument_destroy
      # we don't want any callbacks (sending emails, etc) to happen
      Copilot::Seat.where(seat_assignment: self).each do |seat|
        Copilot::Instrumenter.instrument_copilot_for_business_seat_cancelled(
          seat,
          nil,
          false,
          :cancel_immediately
        )
        seat.delete
      end
      destroy
    end

    sig { returns(T::Boolean) }
    memoize def requires_conversion?
      return false if symbolized_assignable_type == :ORGANIZATION_INVITATION

      seat_member_difference > 0
    end

    sig { returns(Integer) }
    def seat_count
      seats.size
    end

    sig { returns(Integer) }
    memoize def seat_member_difference
      # Difference between the number of members that are eligible for seats and the number of seats that actually
      # exist for members of the team (i.e. does this assignment need to be converted?)
      (assignable_members_eligible_for_seats_count - assignable_member_seat_count).abs
    end

    sig { returns(Integer) }
    memoize def assignable_members_eligible_for_seats_count
      suspended_count = 0

      # reduce the number of ids in the IN statement by slicing, teams can be very large
      assignable_member_ids.each_slice(1000) do |member_ids|
        suspended_count += ::User.where(id: member_ids).suspended.count
      end

      assignable_count - suspended_count
    end

    sig { returns(Integer) }
    memoize def assignable_count
      assignable_member_ids.size
    end

    sig { returns(T::Array[Integer]) }
    memoize def assignable_member_ids
      case symbolized_assignable_type
      when :USER, :ORGANIZATION_INVITATION
        [assignable_id]
      when :TEAM
        if assignable.organization.feature_enabled?(:copilot_child_teams)
          Team.member_ids_of(assignable.id, immediate_only: false)
        else
          assignable.member_ids
        end
      when :ORGANIZATION
        assignable.member_ids
      when :ENTERPRISE_TEAM
        assignable.member_user_ids
      else
        []
      end
    end

    sig { returns(Symbol) }
    def self.default_event_prefix
      :copilot_seat_assignment
    end

    # have to add this because of the polymorphic association and User/Organization kerfuffle
    sig { params(organization: ::Organization).returns(T.nilable(Copilot::SeatAssignment)) }
    def self.organization_seat_assignment(organization)
      self.for_organization(organization).where(
        assignable_type: "Organization",
        assignable_id: organization.id,
      ).first
    end

    sig { params(business: ::Business).returns(T::Array[Copilot::SeatAssignment]) }
    def self.for_business(business)
      organizations = business.organizations.to_a
      Copilot::SeatAssignment.where(organization: organizations).to_a
    end

    sig { params(business: ::Business).returns(T::Array[Copilot::SeatAssignment]) }
    def self.for_standalone_business(business)
      return [] unless Copilot::Business.new(business).copilot_standalone?
      Copilot::SeatAssignment
        .includes(:seats, assignable: { enterprise_team_group_mappings: :external_group })
        .where(owner: business)
        .where(assignable_type: "EnterpriseTeam")
        .order(:created_at)
        .to_a
        .filter { |sa| sa.assignable.present? }
    end

    sig { void }
    def make_sorbet_happy
      @skip_delayed_converter_job = T.let(nil, T.nilable(T::Boolean))
    end

    sig { returns(T::Boolean) }
    def pending_cancellation_today?
      return false unless pending_cancellation_date.present?

      pending_cancellation_date <= Date.current
    end

    sig { returns(T::Boolean) }
    def pending_cancellation?
      pending_cancellation_date.present?
    end

    sig { void }
    def copy_organization_to_owner
      return if self.owner.present? # put this first
      return unless organization.present?

      self.owner = organization
      self.owner_type = "Organization"
    end

    sig { void }
    def owner_must_be_correct_type
      return if assignable.nil? # we don't have an assignable to check yet

      # make sure that we have an owner
      copy_organization_to_owner
      return if owner.nil?

      case symbolized_assignable_type
      when :ENTERPRISE_TEAM
        unless owner.is_a?(::Business)
          errors.add(:owner, "must be a Business")
        end
      when :USER
        unless owner.is_a?(::Organization) || owner.is_a?(::Business)
          errors.add(:owner, "must be an Organization or Business")
        end
      else
        unless owner.is_a?(::Organization)
          errors.add(:assignable, "owner must be an Organization")
        end
      end
    end

    sig { void }
    def assignable_belongs_to_owner
      return if assignable.nil? # we don't have an assignable to check yet

      # make sure that we have an owner
      copy_organization_to_owner
      return if owner.nil?

      case symbolized_assignable_type
      when :ENTERPRISE_TEAM
        enterprise_team = T.cast(assignable, ::EnterpriseTeam)
        unless enterprise_team.business == owner # use the objects, not the id because we want to check type as well
          errors.add(:assignable, "must belong to the owner")
        end
      when :ORGANIZATION
        self.assignable_type = "Organization" # Organizations are Users, Einhorn is Finkle
        assignable_org = T.cast(assignable, ::Organization)
        unless assignable_org.id == owner.id # check the id since we know it's an org
          errors.add(:assignable, "must be the same organization")
        end
      when :USER
        # HEADS UP!!!
        # Because we want to be able to create revoked seat assignments for users who may have been removed
        # from an organization or enterprise, we need to skip validating that a user is a member of those
        # entities.
        # This means that you must make sure to only create a seat assignment in an environment where you
        # are certain the user DID belong to the organization or enterprise.
        return if owner.feature_enabled?(:copilot_revokable_access)

        user = T.cast(assignable, ::User) # this is a single User, how nice
        unless owner.member_ids.include?(user.id) # check the id since we know it's an org
          errors.add(:assignable, "must belong to the organization")
        end
      when :TEAM
        team = T.cast(assignable, ::Team)
        unless team.organization_id == owner.id # check the id since we know it's an org
          errors.add(:assignable, "must belong to the organization")
        end
      when :ORGANIZATION_INVITATION
        invitation = T.cast(assignable, ::OrganizationInvitation)
        unless invitation.organization_id == owner.id
          errors.add(:assignable, "must belong to the organization")
        end
      end
    end

    sig { void }
    def assigning_user_can_assign
      return if assigning_user.nil?

      # make sure that we have an owner
      copy_organization_to_owner
      return if owner.nil?

      if user_is_bot_with_invalid_access?
        errors.add(:assigning_user, "installation does not have write permissions for organization_copilot_seat_management resource.")
      end

      if !T.must(assigning_user).bot? && !owner.member?(T.must(assigning_user))
        owner_type = owner.is_a?(::Business) ? "enterprise" : "organization"
        errors.add(:assigning_user, "must belong to the #{owner_type}")
      end
    end

    sig { void }
    def assignable_not_suspended
      case assignable_type
      when "Organization"
        errors.add(:assignable, "Seat assignment cannot be created for a suspended organization") if assignable.is_a?(::Organization) && T.cast(assignable, ::Organization).suspended?
      when "User"
        unless owner.feature_enabled?(:copilot_revokable_access)
          errors.add(:assignable, "Seat assignment cannot be created for a suspended user") if assignable.is_a?(::User) && T.cast(assignable, ::User).suspended?
        end
      end
    end

    sig { void }
    def owner_not_suspended
      case owner_type
      when "Organization"
        errors.add(:owner, "Seat assignment cannot be created by a suspended organization") if owner.is_a?(::Organization) && T.cast(owner, ::Organization).suspended?
      when "Business"
        errors.add(:owner, "Seat assignment cannot be created by a suspended business") if owner.is_a?(::Business) && T.cast(owner, ::Business).suspended?
      end
    end

    sig { void }
    def delayed_converter_job
      return if symbolized_assignable_type == :ORGANIZATION_INVITATION

      GitHub.logger.info(
        "Queuing delayed_converter_job",
        "gh.copilot.seat_assignment.id" => id,
        "gh.copilot.seat_assignment.assignable_type" => assignable_type,
      )

      Copilot::SeatManagement::SeatAssignmentConverterJob.
        set(wait: COPILOT_SEAT_COOLDOWN_PERIODS[symbolized_assignable_type])
        .perform_later(seat_assignment_id: id.to_i)
    end

    sig { void }
    def auth_and_capture_job
      return unless owner.feature_enabled?(:copilot_auth_on_seat_assignment_creation)

      # We never want to run auth and capture for business-owned seats
      return unless owner_type == "Organization"
      return if owner.business.present?

      # We only want to do this for the first seat assignment created. If we do end up doing this twice,
      # it's not a disaster, since the job itself will noop if an auth check has already happened for this org.
      #
      # Since we never create seat assignments in a single bulk query, we can be confident that this will always
      # trigger for the first seat assignment.
      return if Copilot::SeatAssignment.for_owner(owner).count > 1

      GitHub.logger.info(
        "Queuing auth and capture job",
        "gh.copilot.seat_assignment.id" => id,
        "gh.copilot.seat_assignment.assignable_type" => assignable_type,
      )

      # We set a small delay here so that if the admin creates a bunch of seats or assignments at once,
      # we get a chance to auth for a higher amount than just the first seat.
      Copilot::Billing::OrganizationAuthAndCaptureJob
        .set(wait: 2.minutes)
        .perform_later(
          owner.id,
          skip_account_age_check: true,
          audit_log_reason: "seat_assignment_creation")

      ## Queue up more delayed auth and capture checks for untrusted orgs
      is_untrusted = TrustTiers::Tier.for_billable_owner(owner).tier >= TrustTiers::Tier::NEUTRAL
      return unless is_untrusted && owner.feature_enabled?(:copilot_delayed_auth_on_seat_assignment_creation)

      # Seeded randomness to prevent running more than 2 of these jobs per org by queueing them to start at wildly different times
      srand(owner.id)
      # Delayed auth check within the first 3 hours
      random_delay_minutes = rand(15...(3 * 60))
      Copilot::Billing::OrganizationAuthAndCaptureJob
        .set(wait: random_delay_minutes.minutes)
        .perform_later(
          owner.id,
          skip_previous_authorizations_check: true, # Run check even if others have already run in the last month.
          skip_account_age_check: true, # Skip age check - for orgs this is done against the org owner age
          audit_log_reason: "seat_assignment_creation_delayed_check")
    end

    sig { params(user: ::User).returns(T::Boolean) }
    def includes_user?(user)
      case symbolized_assignable_type
      when :ENTERPRISE_TEAM
        team = T.cast(assignable, ::EnterpriseTeam)
        team.member_user_ids.include?(user.id)
      when :ORGANIZATION
        org = T.cast(assignable, ::Organization)
        user.organizations.include?(org)
      when :TEAM
        team = T.cast(assignable, ::Team)
        team.member_ids.include?(user.id)
      when :USER
        user.id == assignable_id
      when :ORGANIZATION_INVITATION
        invitation = T.cast(assignable, ::OrganizationInvitation)
        invitation.invitee_id == user.id
      else
        false
      end
    end

    sig { returns(T.any(Copilot::Organization, Copilot::Business)) }
    def copilot_owner
      # TODO: remove this method once we have fully transitioned to Owners and away from Organizations
      make_sure_owner_is_populated!

      case owner_type
      when "Business"
        Copilot::Business.new(owner)
      when "Organization"
        Copilot::Organization.new(owner)
      else
        raise "Unknown owner_type: #{owner_type}"
      end
    end

    # TODO: remove this method once we have fully transitioned to Owners and away from Organizations
    sig { void }
    def make_sure_owner_is_populated!
      return if self.owner.present?

      GitHub.dogstats.increment("copilot.seat_assignment.make_sure_owner_is_populated")

      with_write do
        copy_organization_to_owner
        save(validate: false)
      end
    end

    sig { params(unassigning_user: T.nilable(::User), event_type: Symbol).void }
    def unassign!(unassigning_user, event_type = :updated)
      with_write do
        case assignable
        when ::OrganizationInvitation
          event_type = :invitation_destroyed
          destroy!
        else
          if in_cooldown_period? && owner&.feature_enabled?(:copilot_destroy_seat_assignment_in_cooldown_period)
            Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_unassigned(
              self,
              unassigning_user,
              :unassigned_during_cooldown, # event_type is not allowlisted and the user won't see it
              { unassigned_during_cooldown: true } # the user will see this in the audit log API and UI
            )

            destroy!
            return
          end

          # this copies the value over but doesn't save it
          copy_organization_to_owner

          # so there is a chance we get here and the owner has been deleted
          # in that case we need to just destroy the seat assignment
          if (organization.nil? || owner.nil?) && !owner.feature_enabled?(:copilot_revokable_access)
            destroy!
            return
          end

          if assignable_type == "User" && assignable&.suspended? && !owner.feature_enabled?(:copilot_revokable_access)
            destroy!
            return
          end

          # we want to prevent seat assignments that haven't been cleaned up by the PendingSeatAssignmentsJob yet
          # but already have a pending cancellation date from being pushed into the next billing cycle
          if self.pending_cancellation?
            GitHub.logger.info(
              "SeatAssignment was already pending cancellation",
              "gh.copilot.seat_assignment.id" => id,
              "gh.copilot.seat_assignment.assignable_type" => assignable_type,
              "gh.copilot.seat_assignment.assignable.id" => assignable_id,
              "gh.copilot.seat_assignment.owner_id" => owner_id
            )
            return
          end

          self.pending_cancellation_date = owner.next_metered_billing_cycle_starts_at
          # Due to the way installations work, validation will fail when the record is being updated by a bot (GitHub App)
          # therefore we want to skip validation on save
          self.save(validate: false)
        end
      end

      Copilot::Instrumenter.instrument_copilot_for_business_seat_assignment_unassigned(
        self,
        unassigning_user,
        event_type,
      )

      instrument :unassign!
    end

    # This method should be used when we need to revoke Copilot access for a user's seat assignment.
    # We don't always want to revoke access when we unassign, but we do want to unassign whenever we revoke access.
    sig { params(unassigning_user: T.nilable(::User), reason: Symbol, details: T::Hash[Symbol, T.untyped], force: T::Boolean).void } # rubocop:disable Sorbet/ForbidTUntyped
    def unassign_and_revoke_access!(unassigning_user, reason, details = {}, force: false)
      unassign!(unassigning_user, reason)

      unless self.destroyed?
        revoke_access!(reason, details, force: force)
      end
    end

    # Private method! Use unassign_and_revoke_access! instead.
    sig { params(reason: Symbol, details: T::Hash[Symbol, T.untyped], force: T::Boolean).void } # rubocop:disable Sorbet/ForbidTUntyped
    def revoke_access!(reason, details = {}, force: false)
      # We don't want to use symbolized_assignable_type here because we could be revoking access for a user who was deleted.
      # The existence of the user doesn't matter in this case, because the org or enterprise that purchased a Copilot seat
      # should be paying for the entire (prorated) month the seat exists, regardless of whether the user is still around.

      # TODO I'm fairly certain this assumption is actually wrong. In the case of any billing issues,
      # we do want to revoke access to whatever seat assignment the user gets their seat from.
      if assignable_type != "User" && !force
        error = Copilot::Errors::SeatAssignmentError.new("Assignable type must be user when revoking access")
        Copilot::ErrorReporter.report!(
          error,
          copilot_seat_assignment: self
        )
        raise error
      end

      if access_revoked?
        GitHub.logger.info(
          "Seat assignment access already revoked",
          "gh.copilot.seat_assignment.id" => id,
          "gh.copilot.seat_assignment.assignable.id" => assignable.id,
          "gh.copilot.owner.id" => owner.id,
          "gh.copilot.owner.type" => owner_type
        )
        return
      end

      GitHub.logger.info("Revoking access to Copilot: #{reason}",
        "gh.copilot.seat_assignment.id" => id,
        "gh.copilot.seat_assignment.assignable.id" => assignable_id,
        "gh.copilot.owner.id" => owner.id,
        "gh.copilot.owner.type" => owner_type
      )

      Copilot::Instrumenter.instrument_copilot_user_access_revoked(self, reason, details)

      update_attribute(:access_revoked_at, Time.now)

      GitHub.dogstats.increment("copilot.seat_assignment.access_revoked", tags: ["reason:#{reason}"])
    end

    sig { params(reason: Symbol, details: T::Hash[Symbol, T.untyped], options: T::Hash[Symbol, T.untyped]).void } # rubocop:disable Sorbet/ForbidTUntyped
    def reinstate_access!(reason, details = {}, options: {})
      allow_non_user = options[:allow_non_user] || false
      uncancel = options[:uncancel] || false
      extra_params = options[:extra_params] || {}

      if symbolized_assignable_type != :USER && !allow_non_user
        error = Copilot::Errors::SeatAssignmentError.new("Assignable type must be user when reinstating access")
        Copilot::ErrorReporter.report!(
          error,
          copilot_seat_assignment: self
        )
        raise error
      end

      return if access_revoked_at.nil?

      GitHub.logger.info("Reinstating access to Copilot: #{reason}",
        "gh.copilot.seat_assignment.id" => id,
        "gh.copilot.seat_assignment.assignable.id" => assignable.id,
        "gh.copilot.owner.id" => owner.id,
        "gh.copilot.owner.type" => owner_type
      )

      Copilot::Instrumenter.instrument_copilot_user_access_reinstated(self, reason, details)

      attributes = { access_revoked_at: nil }
        .merge(extra_params)
        .tap { |attrs| attrs[:pending_cancellation_date] = nil if uncancel }

      update_columns(attributes)

      # TODO: potentially tag with reason depending how many we have
      GitHub.dogstats.increment("copilot.seat_assignment.access_reinstated")
    end

    sig { returns(GitHub::Result) }
    def convert_to_seats
      # we need to see if this is the first seat assignment for the organization to convert
      GitHub::Result.new do
        instrument :convert_to_seats

        # all of these go through SeatCreation#insert_seats which instruments the creation of seats
        case symbolized_assignable_type
        when :USER
          Copilot::SeatAssignments::UserConverterCommand.call(self)
        when :ORGANIZATION
          Copilot::SeatAssignments::OrganizationConverterCommand.call(self)
        when :TEAM
          Copilot::SeatAssignments::TeamConverterCommand.call(self)
        when :ENTERPRISE_TEAM
          Copilot::SeatAssignments::EnterpriseTeamConverterCommand.call(self)
        else
          # we do nothing for organization invitations
          raise Copilot::Errors::SeatAssignmentError.new("Cannot convert organization invitation to seats")
        end
      end
    end

    sig { returns(Symbol) }
    def symbolized_assignable_type
      return :ORGANIZATION_INVITATION if assignable.is_a?(::OrganizationInvitation)
      return :ORGANIZATION if assignable.is_a?(::Organization)
      return :TEAM if assignable.is_a?(::Team)
      return :ENTERPRISE_TEAM if assignable.is_a?(::EnterpriseTeam)
      return :USER if assignable.is_a?(::User)
      :INVALID
    end

    # It's possible for the assigning_user to be a bot if (un)assignment is happening via a GitHub App installation.
    # In order to assign or unassign seats, the installation must have write access to the Organization resource
    # organization_copilot_seat_management
    sig { returns(T::Boolean) }
    def user_is_bot_with_invalid_access?
      T.must(assigning_user).bot? && !T.must(organization).resources.organization_copilot_seat_management.writable_by?(assigning_user)
    end

    sig { returns(T::Boolean) }
    def access_revoked?
      access_revoked_at.present?
    end

    sig { returns(T::Hash[Symbol, String]) }
    def audit_log_payload
      assignable_identifier = case assignable
      when ::Organization
        assignable&.display_login
      when ::OrganizationInvitation
        assignable.invitee&.display_login
      when ::User
        assignable&.display_login
      when ::Team
        assignable&.name
      when ::EnterpriseTeam
        assignable&.slug
      end
      {
        assignee: assignable_identifier,
        assignee_type: assignable_type,
        pending_cancellation_date: pending_cancellation_date&.iso8601,
        created_at: created_at&.iso8601,
        access_revoked_at: access_revoked_at&.iso8601,
      }
    end

    batch_method(:copilot_sku) do |assignments|
      # load the owner associations for all the assignments
      if GitHub.flipper[:use_billing_locked_rather_than_disabled].enabled?
        GitHub::PrefillAssociations.prefill_associations(assignments, { owner: [:customer_accounts, :customer] })
      else
        GitHub::PrefillAssociations.prefill_associations(assignments, :owner)
      end

      # this is really assignment since this is an instance method
      assignments.index_with do |seat_assignment|
        next :COPILOT_FOR_BUSINESS_BILLING_LOCKED if seat_assignment.owner.disabled?

        case seat_assignment.owner_type
        when "Organization"
          GitHub::PrefillAssociations.prefill_associations(seat_assignment.owner, :business)
          next seat_assignment.copilot_sku_for_org(seat_assignment.owner)
        when "Business"
          # the seat belongs to a business, so it's a standalone seat
          :COPILOT_STANDALONE_SEAT_ASSIGNMENT
        else
          # this is really bad if we get here
          # send an error to sentry
          error = Copilot::Errors::SeatAssignmentError.new("Seat assignment owner type is invalid")

          Copilot::ErrorReporter.report!(
            error,
            copilot_seat_assignment: seat_assignment
          )

          raise error
        end
      end
    end

    sig { params(org: ::Organization).returns Symbol }
    def copilot_sku_for_org(org)
      copilot_org = Copilot::Organization.new(org)
      return :COPILOT_ENTERPRISE_SEAT_ASSIGNMENT if copilot_org.copilot_plan_enterprise?

      :COPILOT_FOR_BUSINESS_SEAT_ASSIGNMENT
    end

    sig { returns(String) }
    def assignable_display_name
      case assignable
      when ::User, ::Organization
        assignable.display_login
      when ::Team, ::EnterpriseTeam
        assignable.name
      when ::OrganizationInvitation
        assignable.email_or_invitee_name
      else
        ""
      end
    end

    # this method will check the number of seats for the membership of each assignable type
    # for a user assignable - we check if that user has a seat
    # for a team assignable - we check if the members of the team have seats
    # for an organization assignable - we check if the members of the organization have seats
    # for an enterprise team assignable - we check if the members of the enterprise team have seats
    sig { returns(Integer) }
    memoize def assignable_member_seat_count
      GitHub.logger.with_named_tags(
        "code.function" => __method__,
        "code.namespace" => self.class.name,
        "gh.org.id" => organization_id,
        "gh.copilot.seat_assignment.id" => id,
      ) do
        case symbolized_assignable_type
        when :USER
          seat_count = Copilot::Seat.for_assigned_user_and_owner(assignable, owner).count
          GitHub.logger.info(
            "Seat count for user",
            "gh.copilot.seat_assignment.seat_count" => seat_count,
          )
          return seat_count if seat_count <= 1

          # so, we're here because the user has more than one seat
          # this is what the kids refer to as an "exceptional situation"
          # we should never have more than one seat for a user
          # this probably won't ever happen but then again, GitHub
          Copilot::ErrorReporter.report!(
            Copilot::Errors::MultipleSeatsForAssignableError.new("Multiple seats for user"),
            copilot_user: assignable,
            copilot_seat_assignment: self
          )

          # we're going to return 1 here because we don't want to break the world
          1
        when :TEAM
          member_ids = if assignable.organization.feature_enabled?(:copilot_child_teams)
            Team.member_ids_of(assignable.id, immediate_only: false)
          else
            assignable.member_ids
          end
          seat_count = Copilot::Seat.for_assigned_user_and_owner(member_ids, owner).count
          GitHub.logger.info(
            "Seat count for team",
            "gh.copilot.seat_assignment.seat_count" => seat_count,
            "gh.copilot.seat_assignment.member_ids_count" => member_ids.size,
          )
          seat_count
        when :ORGANIZATION
          member_ids = assignable.member_ids

          seat_count = Copilot::Seat.for_assigned_user_and_owner(member_ids, owner).count
          GitHub.logger.info(
            "Seat count for organization",
            "gh.copilot.seat_assignment.seat_count" => seat_count,
            "gh.copilot.seat_assignment.member_ids_count" => member_ids.size,
          )
          seat_count
        when :ENTERPRISE_TEAM
          member_ids = assignable.member_user_ids

          # owner here is a Business
          seat_count = Copilot::Seat.for_assigned_user_and_owner(member_ids, owner).count
          GitHub.logger.info(
            "Seat count for enterprise team",
            "gh.copilot.seat_assignment.seat_count" => seat_count,
            "gh.copilot.seat_assignment.member_ids_count" => member_ids.size,
          )
          seat_count
        when :ORGANIZATION_INVITATION
          0
        else
          # what is this I don't even
          Copilot::ErrorReporter.report!(
            Copilot::Errors::UnknownAssignableTypeError.new("Unknown assignable type #{assignable_type}"),
            copilot_seat_assignment: self,
          )
          0
        end
      end
    end

    # Determine whether the seat was created earlier than the seat delay, determined by the assignable type
    sig { returns(T::Boolean) }
    def in_cooldown_period?
      # since symbolize_assignable_type checks the actual type of the assignable, we need to do this
      # in instances where the assignable has been destroyed and hence symbolized_assignable_type is :INVALID
      # (which is fine, the assignment will be destroyed anyway).  It could also be an OrganizationInvitaiton, which
      # would have been destroyed in unassign! before this code path gets hit.
      return false if !Copilot::COPILOT_SEAT_COOLDOWN_PERIODS.include?(symbolized_assignable_type)

      cooldown_time = Copilot::COPILOT_SEAT_COOLDOWN_PERIODS[symbolized_assignable_type]&.ago
      in_cooldown = created_at > cooldown_time

      if in_cooldown # doing this so I can dogstat before feature flag is on
        GitHub.dogstats.increment("copilot.seat_assignment.unassigned_within_cooldown")
        GitHub.logger.info(
          "SeatAssignment was unassigned within cooldown period",
          "gh.copilot.seat_assignment.id" => id,
          "gh.copilot.seat_assignment.assignable_type" => assignable_type,
          "gh.copilot.seat_assignment.assignable.id" => assignable_id,
          "gh.copilot.seat_assignment.owner.id" => owner_id,
          "gh.copilot.seat_assignment.owner.type" => owner_type,
          "gh.copilot.seat_assignment.assignable_member_count" => assignable_count,
        )
      end

      in_cooldown
    end

    private

    sig { void }
    def instrument_create
      instrument :create
    end

    sig { void }
    def instrument_update
      instrument :update
    end

    sig { void }
    def instrument_destroy
      instrument :destroy
    end

    sig do
      returns({
        organization: T.nilable(::Organization),
        owner: T.nilable(T.any(::Business, ::Organization)),
        assignable_type: String,
        assignable_id: Integer,
        pending_cancellation_date: T.nilable(Date),
        assigning_user: T.nilable(::User),
        access_revoked_at: T.nilable(Time),
      })
    end
    def event_payload
      {
        organization: organization,
        owner: owner,
        assignable_type: assignable_type,
        assignable_id: assignable_id,
        pending_cancellation_date: pending_cancellation_date,
        assigning_user: assigning_user,
        access_revoked_at: access_revoked_at,
      }
    end

    sig { params(assc: Copilot::Seat).void }
    def destroy_when_empty(assc)
      destroy! if self.seats.size == 0 && assignable_type == "User"
    end
  end
end
