# typed: strict
# frozen_string_literal: true

module Copilot
  class Seat < ApplicationRecord::Copilot
    include ::Instrumentation::Model
    include Copilot::Helpers
    include GitHub::Memoizer
    include Copilot::Seat::BillingDependency
    include Copilot::SeatManagement::SeatAssignmentHelpers

    self.table_name = "copilot_seats"
    self.strict_loading_by_default = true

    sig { params(customer_id: T.nilable(Integer)).returns(T.nilable(Integer)) }
    attr_writer :customer_id

    belongs_to :organization, class_name: "::Organization", strict_loading: false
    # rubocop:todo Rails/InverseOf
    belongs_to :assigned_user, class_name: "::User", foreign_key: :assigned_user_id, strict_loading: false
    belongs_to :seat_assignment, class_name: "Copilot::SeatAssignment", foreign_key: :copilot_seat_assignment_id, strict_loading: false
    has_one :seat_history, class_name: "Copilot::SeatHistory", foreign_key: :seat_id, inverse_of: :seat, strict_loading: false
    # rubocop:enable Rails/InverseOf

    validates :assigned_user, presence: true
    validates :assigned_user, uniqueness: { scope: [:organization, :seat_assignment] }
    validates :seat_assignment, presence: true

    validate :assigned_user_belongs_to_owner
    validate :seat_assignment_includes_assigned_user

    after_create         :generate_seat_history!
    after_destroy_commit :history_deletion
    after_destroy_commit :unset_billable_customer_id

    delegate :owner, :symbolized_assignable_type, to: :seat_assignment

    scope :for_organization, ->(organization) { where(organization: organization) }
    scope :for_owner, ->(owner) do
      joins(:seat_assignment).where(copilot_seat_assignments: { owner_id: owner.id, owner_type: owner.class.name })
    end
    scope :for_user, ->(user) { where(assigned_user: user) }

    # This method can accept a user object, a user id, or an array of user ids
    scope :for_assigned_user_and_owner, ->(user, owner) do
      if owner.is_a?(::Business)
        Copilot::Seat.joins(:seat_assignment).where(assigned_user: user).where(copilot_seat_assignments: { owner: owner })
      else
        Copilot::Seat.joins(:seat_assignment).where(assigned_user: user).where(copilot_seat_assignments: { owner_type: "Organization", owner_id: owner.id })
      end
    end

    scope :for_assigned_user_ids_and_owner, ->(user_ids, owner) do
      if owner.is_a?(::Business)
        Copilot::Seat.joins(:seat_assignment).where(assigned_user_id: user_ids).where(copilot_seat_assignments: { owner: owner })
      else
        Copilot::Seat.joins(:seat_assignment).where(assigned_user_id: user_ids).where(copilot_seat_assignments: { owner_type: "Organization", owner_id: owner.id })
      end
    end

    scope :for_standalone_business, ->(owner) do
      joins(:seat_assignment).where(
        copilot_seat_assignments: {
          owner_type: "Business",
          owner_id: owner.id,
          assignable_type: %w(EnterpriseTeam User)
        }
      )
    end

    scope :without_access_revoked, ->(owner:) do
      for_owner(owner)
        .where(copilot_seat_assignments: { access_revoked_at: nil })
    end
    scope :without_access_revoked_for_user, ->(user) do
      joins(:seat_assignment).where(copilot_seat_assignments: { access_revoked_at: nil }).where(assigned_user: user)
    end

    scope :business_owned, ->(owner) do
      joins(:seat_assignment).where(
        copilot_seat_assignments: {
          owner_type: "Business",
          owner_id: owner.id,
          organization_id: nil,
          assignable_type: %w(User BusinessTeam)
        }
      )
    end

    # Returns a list of seats for the given owner_ids and user_ids where a user has multiple seats and at least one of them is not pending cancellation.
    sig { params(owner_ids: T::Array[T.nilable(Integer)], user_ids: T::Array[Integer]).returns(T::Array[Copilot::Seat]) }
    def self.multi_org_users_with_active_seat(owner_ids:, user_ids:)
      return Copilot::Seat.none.to_a if owner_ids.blank? || user_ids.blank?

      Copilot::Seat
        .find_by_sql(
          <<-SQL
            SELECT assigned_user_id, copilot_seat_assignment_id
            FROM copilot_seats
            INNER JOIN copilot_seat_assignments ON copilot_seats.copilot_seat_assignment_id = copilot_seat_assignments.id
            WHERE copilot_seat_assignments.owner_id IN (#{owner_ids.join(',')})
              AND copilot_seat_assignments.owner_type = 'Organization'
            AND assigned_user_id IN (#{user_ids.join(',')})
            GROUP BY assigned_user_id
            HAVING COUNT(*) != COUNT(copilot_seat_assignments.pending_cancellation_date)
          SQL
        )
    end

    sig { params(business: ::Business).returns(T::Array[Copilot::Seat]) }
    def self.for_business(business)
      if Copilot::Business.new(business).copilot_standalone?
        Copilot::Seat.for_owner(business).to_a
      else
        organizations = business.organizations.to_a
        seats = Copilot::Seat.where(organization: organizations).to_a
        if business.can_assign_copilot_to_business_users?
          seats += Copilot::Seat.business_owned(business).to_a
        end
        seats
      end
    end

    sig { params(business: ::Business, user_ids: T.any(::Integer, T::Array[::Integer])).returns(ActiveRecord::Relation) }
    def self.for_business_user_ids(business, user_ids)
      if Copilot::Business.new(business).copilot_standalone?
        scope = Copilot::Seat.for_owner(business)
      else
        organization_ids = business.organization_ids
        if business.can_assign_copilot_to_business_users?
          # Seat assignment isn't necessary, adding it to keep the queries stucturally compatible
          scope = Copilot::Seat.joins(:seat_assignment).where(organization_id: organization_ids)
          scope = scope.or(Copilot::Seat.business_owned(business))
        else
          scope = Copilot::Seat.where(organization_id: organization_ids)
        end
      end

      scope.where(assigned_user_id: user_ids)
    end

    sig { params(assignable_id: T.any(::User, Integer, T::Array[Integer]), org: ::Organization).returns(T.nilable(Copilot::Seat)) }
    def self.for_assignable_in_org(assignable_id, org)
      # for non-user assignables, assignable_id might be a list of ids
      Copilot::Seat.includes(:seat_assignment).for_user(assignable_id).for_organization(org).first
    end

    sig { params(assignable_id: T.any(::User, Integer, T::Array[Integer]), business: ::Business).returns(T.nilable(Copilot::Seat)) }
    def self.for_assignable_in_business(assignable_id, business)
      Copilot::Seat.includes(:seat_assignment).for_user(assignable_id).for_owner(business).first
    end

    # Returns a value that will ultimately determine the order in which the SKUs are sorted.
    # The lower the value, the higher the priority.
    # Ultimately, Copilot Business Trial > Copilot Enterprise Trial > Copilot Enterprise > Copilot Business = Copilot Standalone
    sig { params(sku: Symbol).returns(Integer) }
    def self.priority_for_copilot_sku(sku)
      case sku
      when :COPILOT_FOR_BUSINESS_TRIAL_SEAT
        0
      when :COPILOT_ENTERPRISE_TRIAL_SEAT, :COPILOT_ENTERPRISE_TRIAL_SEAT_STAFF
        1
      when :COPILOT_ENTERPRISE_SEAT
        2
      when :COPILOT_FOR_BUSINESS_SEAT, :COPILOT_STANDALONE_SEAT
        3
      else # Note that :COPILOT_FOR_BUSINESS_BILLING_LOCKED falls into this case
        4
      end
    end


    sig { params(seats: T.any(ActiveRecord::Relation, T::Array[Copilot::Seat])).returns(T::Hash[Integer, T::Hash[Symbol, String]]) }
    def self.seat_plan_types_by_owner_type(seats)
      seats.inject({}) do |memo, seat|
        assignment = seat.seat_assignment

        next memo if assignment.nil?

        owner_type = assignment.owner_type

        next memo if memo[assignment.id]

        if owner_type == "Business"
          plan = assignment.assignable_type == "User" ? "business" : Copilot::Business.new(assignment.owner).copilot_plan
        else
          plan = Copilot::Organization.new(assignment.owner).copilot_plan
        end

        memo[assignment.id] = { plan: plan }
        memo
      end
    end

    sig { returns(ActiveSupport::TimeWithZone) }
    def next_metered_billing_cycle_starts_at
      T.must(seat_assignment).assignable_type == "EnterpriseTeam" ? T.must(seat_assignment).owner.next_metered_billing_cycle_starts_at : T.must(T.must(seat_assignment).organization).next_metered_billing_cycle_starts_at
    end

    sig { returns(T.nilable(Date)) }
    def pending_cancellation_date
      T.must(seat_assignment).pending_cancellation_date
    end

    sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def access_revoked_at
      seat_assignment&.access_revoked_at
    end

    # Non-public method. See stafftools/paginated_seats_component
    sig { returns(T.nilable(Time)) }
    def latest_activity_at
      return nil if assigned_user.nil?
      latest = Copilot::Activity.for_seat(self)

      return nil if latest.nil?

      latest.activity_at.time
    end

    sig { void }
    def assigned_user_belongs_to_owner
      # this can be called before these are set.  like in the validation tests :)
      return if assigned_user.nil? || seat_assignment.nil?

      # if the seat assignment is set but the assignable is blank, we need to tell someone and get out of here
      if T.must(seat_assignment).assignable.nil?
        GitHub.logger.error("Seat assignment has no assignable",
                            "gh.copilot.seat_assignment.id" => seat_assignment&.id,
                            "gh.copilot.seat_assignment.assignable.id" => seat_assignment&.assignable_id,
                            "gh.copilot.seat_assignment.assignable.type" => seat_assignment&.assignable_type,
                            "gh.copilot.seat.id" => id)
        GitHub.dogstats.increment("copilot.seat_assignment_assignable_blank")
        Copilot::ErrorReporter.report!(
          Copilot::Errors::SeatAssignmentAssignableError.new("Seat assignment has no assignable"),
          copilot_seat_assignment: seat_assignment
        )
        errors.add(:seat_assignment, "has no assignable")
        return
      end

      unless T.must(seat_assignment).includes_user?(T.must(assigned_user))
        errors.add(:assigned_user, "must belong to the same owner as the seat assignment")
      end
    end

    sig { void }
    def seat_assignment_includes_assigned_user
      # this can be called before the assigned_user or seat_assignment is set.  like in the validation tests :)
      return if assigned_user.nil? || seat_assignment.nil?

      unless T.must(seat_assignment).includes_user?(T.must(assigned_user))
        errors.add(:assigned_user, "must be included in the assignment")
      end
    end

    sig { params(actor: T.nilable(::User), trial_seat: T::Boolean, staff_cancel: T::Boolean, reason: Symbol).void }
    def cancel!(actor: nil, trial_seat: false, staff_cancel: false, reason: :cancel_immediately)
      GitHub.logger.with_named_tags(
        seat_assignment_log_details(seat_assignment).merge(
          "gh.copilot.seat.id" => id,
          "gh.copilot.seat.trial_seat" => trial_seat,
          "gh.user.id" => assigned_user_id,
        )
      ) do
        GitHub.logger.info("Deleting Copilot seat")

        if assigned_user&.suspended? || assigned_user.nil? || seat_assignment&.access_revoked?
          GitHub.logger.info("Not sending email or creating notification for seat cancellation.")
        else
          notification_id = send_mail(trial_seat)

          create_notification(notification_id, trial_seat, T.must(seat_assignment).owner)
        end

        # Using this construct, we ensure the after_remove callback on the seat_assignment is
        # called. That callback destroys the seat assignment when it is empty.
        # See https://github.com/rails/rails/issues/14365#issuecomment-1192809293
        T.must(seat_assignment).seats.destroy(self)

        # when this is called from the copilot_seats_controller in stafftools, the staff actor is passed
        # otherwise, the actor is nil and the event comes from "GitHub System"
        Copilot::Instrumenter.instrument_copilot_for_business_seat_cancelled(
          self,
          actor,
          staff_cancel,
          reason,
          trial_seat: trial_seat,
        ) if assigned_user.present?
      end
    end

    sig { params(trial_seat: T::Boolean).returns(String) }
    def send_mail(trial_seat)
      GitHub.logger.info("Sending seat cancellation email",
                         "gh.copilot.seat.id" => id,
                         "gh.user.id" => assigned_user_id)
      notification_id = ""

      # we don't have a user to send to
      unless assigned_user.present?
        GitHub.logger.error("Assigned user does not exist",
                            "gh.copilot.seat.id" => id,
                            "gh.user.id" => assigned_user_id)
        return notification_id
      end

      if trial_seat
        notification_id = "cfb_free_trial_ended_#{organization_id}"

        # Email user that their trial has expired
        GitHub.logger.info("Sending trial seat expired email to user",
                           "gh.copilot.seat.id" => id,
                           "gh.user.id" => assigned_user_id)
        CopilotForBusinessMailer.trial_seat_expired_for_user(
          T.must(organization),
          T.must(assigned_user),
        ).deliver_later
      else
        notification_id = "copilot_seat_removed_#{organization_id}"

        GitHub.logger.info("Sending seat removed email to user",
                           "gh.copilot.seat.id" => id,
                           "gh.user.id" => assigned_user_id)
        CopilotForBusinessMailer.seat_removed_for_user(
          organization,
          T.must(assigned_user),
        ).deliver_later
      end

      notification_id
    rescue StandardError => e # rubocop:todo Lint/RescueException
      GitHub.logger.error("Error sending seat cancellation email",
                          "gh.copilot.seat.id" => id)
      Copilot::ErrorReporter.report!(
        Copilot::Errors::CopilotError.from_error(e),
      )
      ""
    end

    sig { params(notification_id: String, trial_seat: T::Boolean, owner: T.nilable(T.any(::Organization, ::Business))).void }
    def create_notification(notification_id, trial_seat, owner)

      # we need to make a notification for the user
      GitHub.logger.info("Creating seat removed notification for user",
                         "gh.copilot.notification.id" => notification_id, "gh.copilot.seat.id" => id)
      unless assigned_user.present?
        GitHub.logger.error("Assigned user does not exist",
                            "gh.copilot.seat.id" => id, "gh.user.id" => assigned_user_id)
        return
      end
      Copilot::EditorNotification.create_for_user(
        T.must(assigned_user),
        notification_id,
        owner,
      )
    end

    sig { params(staff_user: ::User).void }
    def staff_set_pending_cancellation!(staff_user)
      return unless seat_assignment.present?

      assignment = T.must(seat_assignment)

      case assignment.symbolized_assignable_type
      when :USER
        assignment.unassign!(staff_user, :unassigned_by_staff)
      when :ORGANIZATION, :TEAM, :ORGANIZATION_INVITATION
        # We don't want to create new seat assignments for users disassociated from orgs or teams who
        # might be suspended (the call will fail anyway), so let's just clean up the seat immediately.
        if assigned_user&.suspended?
          cancel!(actor: staff_user, staff_cancel: true)
          return
        end

        # need to disassociate this seat from the assignment and create a user assignment
        seat_assignment = Copilot::SeatAssignment.create!(
          owner_type: "Organization",
          owner_id: T.must(organization).id,
          organization: T.must(organization),
          assignable: assigned_user,
          assigning_user: T.must(assignment.organization).admins.first,
        )
        seat_assignment.unassign!(staff_user, :unassigned_by_staff)
      else
        raise "Unknown seat assignment type: #{assignment.symbolized_assignable_type}"
      end

      Copilot::Instrumenter.instrument_copilot_for_business_seat_cancelled(
        self,
        staff_user,
        true,
        :cancel_scheduled,
      )
    end

    sig { params(staff_user: ::User).void }
    def staff_remove_pending_cancellation!(staff_user)
      return unless seat_assignment.present?

      assignment = T.must(seat_assignment)

      case assignment.symbolized_assignable_type
      when :USER
        assignment.pending_cancellation_date = nil
        assignment.save!
      when :ORGANIZATION, :TEAM, :ORGANIZATION_INVITATION
        # need to disassociate this seat from the assignment and create a user assignment
        Copilot::SeatAssignment.create!(
          owner_type: "Organization",
          owner_id: T.must(organization).id,
          organization: T.must(organization),
          assignable: assigned_user,
          assigning_user: staff_user,
        )
      when :ENTERPRISE_TEAM, :BUSINESS_TEAM
        # need to disassociate this seat from the assignment and create a user assignment
        Copilot::SeatAssignment.create!(
          owner_type: "Business",
          owner_id: assignment.owner_id,
          assignable: assigned_user,
          assigning_user: staff_user,
        )
      else
        raise "Unknown seat assignment type: #{assignment.symbolized_assignable_type}"
      end

      Copilot::Instrumenter.instrument_copilot_for_business_seat_uncancelled(
        self,
        staff_user,
      )
    end

    sig { returns(Copilot::SeatHistory) }
    def generate_seat_history!
      history = seat_history || Copilot::SeatHistory.find_by(seat_id: id)

      if history.present?
        # this is okay, we won't get mad
        GitHub.dogstats.increment("copilot.seat_history_job.seat_history_found")
        return history
      end

      # phew, we're cool
      GitHub.dogstats.increment("copilot.seat_history_job.seat_history_not_found")
      start_date, end_date = billing_cycle_info
      business = if owner_type == "Business"
        owner = T.must(seat_assignment).owner
        owner if owner.feature_flag_enabled_or_raise?(:copilot_revokable_access) || owner.can_assign_copilot_to_business_users? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      else
        organization&.business
      end

      # let's create one
      Copilot::SeatHistory.create!(
        seat: self,
        owner_id: owner_id,
        owner_type: owner_type,
        organization_id: organization_id,
        business: business,
        assigned_user: assigned_user,
        seat_created_at: created_at.to_date,
        billing_cycle_start_date: start_date,
        billing_cycle_end_date: end_date
      )
    end

    # Breaking this out into a new method until copilot_revokable_access is finalized.
    # Previously, we were always assuming that seat histories were created for organizations.
    # It seems that we don't create them for enterprise teams at all
    sig { returns(T::Array[Date]) }
    def billing_cycle_info
      owner = if owner_type == "Organization"
        organization
      elsif owner_type == "Business"
        business = T.must(seat_assignment).owner
        business if business.feature_flag_enabled_or_raise?(:copilot_revokable_access) || business.can_assign_copilot_to_business_users? # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      end

      billing_cycle_start_date = owner.present? ? owner.current_metered_billing_cycle_starts_at.to_date : Date.new(9999, 12, 31)
      billing_cycle_end_date = owner.present? ? owner.next_metered_billing_cycle_starts_at.to_date : Date.new(9999, 12, 31)

      [billing_cycle_start_date, billing_cycle_end_date]
    end

    sig { returns(T.nilable(Integer)) }
    def owner_id
      owner_id = organization&.id.to_i

      if seat_assignment.present?
        assignment = T.must(seat_assignment)

        assignable_symbol = assignment.symbolized_assignable_type

        # if this seat assignment is an EnterpriseTeam level one, we should set the owner to business
        if assignable_symbol == :ENTERPRISE_TEAM
          enterprise_team = T.cast(T.must(seat_assignment).assignable, ::EnterpriseTeam)
          owner_id = enterprise_team.business_id
        elsif assignment.owner_type == "Business" && assignable_symbol == :USER && (assignment.owner.feature_flag_enabled_or_raise?(:copilot_revokable_access) || owner.can_assign_copilot_to_business_users?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          owner_id = assignment.owner_id
        end
      end

      owner_id
    end

    sig { returns(String) }
    memoize def owner_type
      owner_type = "Organization"

      if seat_assignment.present?
        assignment = T.must(seat_assignment)

        assignable_symbol = assignment.symbolized_assignable_type

        # if this seat assignment is an EnterpriseTeam level one, we should set the owner to business
        if assignable_symbol == :ENTERPRISE_TEAM
          owner_type = "Business"
        elsif assignment.owner_type == "Business" && assignable_symbol == :USER && (assignment.owner.feature_flag_enabled_or_raise?(:copilot_revokable_access) || owner.can_assign_copilot_to_business_users?) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
          owner_type = assignment.owner_type
        end
      end

      owner_type
    end

    sig { void }
    def history_deletion
      with_write do
        # let's load the history for this seat
        #         relation        look it up directly
        history = seat_history || Copilot::SeatHistory.find_by(seat_id: id)

        unless history.present?
          GitHub.dogstats.increment("copilot.seat_history_job.seat_history_not_found")
          history = generate_seat_history!
        end

        # let's update it
        history.update!(seat_deleted_at: Date.current)
      end
    end

    # If the user can no longer bill overages to their preferred billable_customer_id, we should clear it
    # TODO: do we need to call this when revoking access?
    sig { void }
    def unset_billable_customer_id
      user = T.let(assigned_user, T.nilable(::User))
      return unless user.present?
      copilot_user = Copilot::User.new(user)
      # User never set billable_customer_id so there's nothing we need to do
      return unless copilot_user.billable_customer_id.present?

      # User wasn't billing overages to this seat's customer anyway so let's leave it
      return unless copilot_user.billable_customer_id == customer_id

      Copilot::Public::User.new(user).copilot_customer_ids.each do |c_id|
        # User is can still bill to this customer, so we should do nothing
        return if c_id == copilot_user.billable_customer_id
      end

      with_write do
        copilot_user.set_billable_customer_id!(nil)
      end
    end

    sig { returns(T::Hash[Symbol, String]) }
    def audit_log_payload
      {
        seat_id: id,
        created_at: created_at&.iso8601
      }
    end

    sig { returns(T.nilable(Integer)) }
    def customer_id
      return unless owner.present?
      return @customer_id if defined?(@customer_id)

      if owner.feature_flag_enabled_or_raise?(:use_find_or_create_customer) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        @customer_id = owner.find_or_create_customer.id
      elsif owner.is_a?(::Business)
        @customer_id = Copilot::Business.new(owner).customer_for&.id
      elsif owner.is_a?(::Organization)
        @customer_id = copilot_org.customer_for&.id
      end
    end

    sig { returns(Copilot::Organization) }
    memoize def copilot_org
      Copilot::Organization.new(T.must(organization))
    end

    batch_method(:customer_ids) do |seats|
      # load up the seat assignments and owners
      GitHub::PrefillAssociations.prefill_associations(seats, :seat_assignment)
      GitHub::PrefillAssociations.prefill_associations(seats, :assigned_user)
      GitHub::PrefillAssociations.prefill_associations(seats.map(&:seat_assignment), { owner: [:business, :customer] })

      # logically, this seats really is seat because this is an instance method, but i wrote it so you never know
      seats.index_with do |seat|
        next if FeatureFlag.vexi.enabled?("copilot_ignore_access_revoked_for_customer_ids", seat.assigned_user, default: false) && seat.seat_assignment&.access_revoked?
        seat.seat_assignment&.owner&.customer&.id || seat.seat_assignment&.owner&.business&.customer_id
      end
    end

    # |                                      | BusinessTrial | Configuration | Organization | Business |
    # |--------------------------------------|---------------|---------------|--------------|----------|
    # | COPILOT_ENTERPRISE_TRIAL_SEAT        | ENTERPRISE    | BUSINESS      | REQUIRED     | REQUIRED |
    # | COPILOT_FOR_BUSINESS_TRIAL_SEAT      | BUSINESS      | BUSINESS      | REQUIRED     | OPTIONAL |
    # | COPILOT_STANDALONE_SEAT              | NONE          | BUSINESS      | NONE         | REQUIRED |
    # | COPILOT_ENTERPRISE_SEAT              | NONE          | ENTERPRISE    | REQUIRED     | REQUIRED |
    # | COPILOT_FOR_BUSINESS_SEAT            | NONE          | BUSINESS      | OPTIONAL     | OPTIONAL |
    batch_method(:copilot_sku) do |seats|
      # load up the seat assignments and owners
      GitHub::PrefillAssociations.prefill_associations(seats, :seat_assignment)
      if FeatureFlag.vexi.enabled_or_raise?(:use_billing_locked_rather_than_disabled) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        GitHub::PrefillAssociations.prefill_associations(seats.map(&:seat_assignment), { owner: [:customer_accounts, :customer] })
      else
        GitHub::PrefillAssociations.prefill_associations(seats.map(&:seat_assignment), :owner)
      end

      # logically, this seats really is seat because this is an instance method, but i wrote it so you never know
      seats.index_with do |seat|
        # TODO: skip seats with revoked seat assignments here, use .compact in async_seats_check in the authorizer
        case seat.seat_assignment.owner_type
        when "Organization"
          organization = seat.seat_assignment.owner

          GitHub::PrefillAssociations.prefill_associations(organization, :business)

          next :COPILOT_FOR_BUSINESS_BILLING_LOCKED if organization.disabled?

          next seat.seat_copilot_sku_for_org(organization)
        when "Business"
          business = seat.seat_assignment.owner
          # if the seat is not a direct assignment for an unaffiliated user,
          # the seat (through the seat assignment) belongs to a business, so it's a standalone seat
          next :COPILOT_STANDALONE_SEAT unless business.can_assign_copilot_to_business_users?

          # if the business supports unaffiliated users and is not on the basic plan
          # and the feature is enabled, then this is a copilot for business seat (trial if the business is on trial)
          if business.trial?
            :COPILOT_FOR_BUSINESS_TRIAL_SEAT
          else
            :COPILOT_FOR_BUSINESS_SEAT
          end
        else
          # this is really bad if we get here
          # send an error to Sentry
          error = Copilot::Errors::SeatAssignmentError.new("Seat assignment owner type is invalid")
          Copilot::ErrorReporter.report!(
            error,
            copilot_seat_assignment: seat.seat_assignment,
            copilot_seat: seat,
          )

          raise error
        end
      end
    end

    # TODO: Consolidate with copilot_sku method when flag is removed
    sig { params(org: ::Organization).returns(Symbol) }
    def seat_copilot_sku_for_org(org)
      copilot_org = Copilot::Organization.new(org)

      if copilot_org.has_trial?
        # they have a trial, so we need to check the plan of the trial
        # their business' copilot plan in configuration is probably set to business
        created_by_staff_user = T.must(copilot_org.business_trial).was_created_by_staff_user?
        if T.must(copilot_org.business_trial).copilot_plan_enterprise?
          return :COPILOT_ENTERPRISE_TRIAL_SEAT_STAFF if created_by_staff_user
          :COPILOT_ENTERPRISE_TRIAL_SEAT
        else
          :COPILOT_FOR_BUSINESS_TRIAL_SEAT
        end
      else
        # no trial means full seat
        return :COPILOT_ENTERPRISE_SEAT if copilot_org.copilot_plan_enterprise?
        :COPILOT_FOR_BUSINESS_SEAT
      end
    end
  end
end
