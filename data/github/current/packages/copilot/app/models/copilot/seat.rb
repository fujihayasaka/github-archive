# typed: strict
# frozen_string_literal: true

module Copilot
  class Seat < ApplicationRecord::Copilot
    extend T::Sig
    include ::Instrumentation::Model
    include Copilot::Helpers
    include GitHub::Memoizer
    include Copilot::Seat::BillingDependency

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

    delegate :owner, :symbolized_assignable_type, to: :seat_assignment

    scope :for_organization, ->(organization) { where(organization: organization) }
    scope :for_owner, ->(owner) do
      joins(:seat_assignment).where(copilot_seat_assignments: { owner_id: owner.id, owner_type: owner.class.name })
    end
    scope :for_user, ->(user) { where(assigned_user: user) }

    scope :for_assigned_user_and_owner, ->(user, owner) do
      if owner.is_a?(::Business)
        Copilot::Seat.joins(:seat_assignment).where(assigned_user: user).where(copilot_seat_assignments: { owner: owner })
      else
        Copilot::Seat.joins(:seat_assignment).where(assigned_user: user).where(copilot_seat_assignments: { owner_type: "Organization", owner_id: owner.id })
      end
    end

    sig { params(owner: T.any(::Business, ::Organization)).returns(T::Array[Copilot::Seat]) }
    def self.for_owner(owner)
      owner_type = owner.is_a?(::Business) ? "Business" : "Organization"
      Copilot::Seat.includes(:seat_assignment).where(copilot_seat_assignments: { owner_type: owner_type, owner_id: owner.id }).to_a
    end

    sig { params(business: ::Business).returns(T::Array[Copilot::Seat]) }
    def self.for_business(business)
      if Copilot::Business.new(business).copilot_standalone?
        Copilot::Seat.for_owner(business).to_a
      else
        organizations = business.organizations.to_a
        Copilot::Seat.where(organization: organizations).to_a
      end
    end

    sig { params(assignable_id: T.any(::User, Integer, T::Array[Integer]), org: ::Organization).returns(T.nilable(Copilot::Seat)) }
    def self.for_assignable_in_org(assignable_id, org)
      # for non-user assignables, assignable_id might be a list of ids
      Copilot::Seat.includes(:seat_assignment).for_user(assignable_id).for_organization(org).first
    end

    # Returns a value that will ultimately determine the order in which the SKUs are sorted.
    # The lower the value, the higher the priority.
    # Ultimately, Copilot Business Trial > Copilot Enterprise Trial > Copilot Enterprise > Copilot Business = Copilot Standalone
    sig { params(sku: Symbol).returns(Integer) }
    def self.priority_for_copilot_sku(sku)
      case sku
      when :COPILOT_FOR_BUSINESS_TRIAL_SEAT
        0
      when :COPILOT_ENTERPRISE_TRIAL_SEAT
        1
      when :COPILOT_ENTERPRISE_SEAT
        2
      when :COPILOT_FOR_BUSINESS_SEAT, :COPILOT_STANDALONE_SEAT
        3
      else # Note that :COPILOT_FOR_BUSINESS_BILLING_LOCKED falls into this case
        4
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

    sig { returns(T.nilable(Time)) }
    def latest_activity_at
      return nil if assigned_user.nil?
      latest = Copilot::AggregateUsageDetail.latest_for_users(T.must(assigned_user))

      return nil if latest.nil?

      T.must(latest.updated_at).time
    end

    sig { void }
    def assigned_user_belongs_to_owner
      # this can be called before these are set.  like in the validation tests :)
      return if assigned_user.nil? || seat_assignment.nil?

      # if the seat assignment is set but the assignable is blank, we need to tell someone and get out of here
      if T.must(seat_assignment).assignable.nil?
        GitHub.logger.error("Seat assignment has no assignable")
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
      GitHub.logger.with_named_tags({
        "gh.copilot.seat.id" => id,
        "gh.copilot.seat.trial_seat" => trial_seat,
      }) do
        GitHub.logger.info("Deleting seat")

        if assigned_user&.suspended?
          GitHub.logger.info("User is suspended, not sending email or creating notification.",
                             "gh.copilot.seat.id" => id)
        else
          notification_id = send_mail(trial_seat)

          create_notification(notification_id, trial_seat, T.must(seat_assignment).owner)
        end

        # when this is called from the copilot_seats_controller in stafftools, the staff actor is passed
        # otherwise, the actor is nil and the event comes from "GitHub System"
        Copilot::Instrumenter.instrument_copilot_for_business_seat_cancelled(
          self,
          actor,
          staff_cancel,
          reason,
          trial_seat: trial_seat,
        ) if assigned_user.present?

        # Using this construct, we ensure the after_remove callback on the seat_assignment is
        # called. That callback destroys the seat assignment when it is empty.
        # See https://github.com/rails/rails/issues/14365#issuecomment-1192809293
        T.must(seat_assignment).seats.destroy(self)
      end
    end

    sig { params(trial_seat: T::Boolean).returns(String) }
    def send_mail(trial_seat)
      GitHub.logger.info("Sending seat cancellation email",
                         "gh.copilot.seat.id" => id)
      notification_id = ""

      # we don't have a user to send to
      unless assigned_user.present?
        GitHub.logger.error("Assigned user does not exist",
                           "gh.copilot.seat.id" => id)
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
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
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
      GitHub.logger.info("Creating seat removed notification for user", "gh.copilot.notification.id" => notification_id)
      unless assigned_user.present?
        GitHub.logger.error("Assigned user does not exist")
        return
      end
      Copilot::EditorNotification.create_for_user(
        T.must(assigned_user),
        notification_id,
        owner,
      )
    end

    sig { params(staff_user: ::User).void }
    def staff_cancel_pending!(staff_user)
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

        # need to disassociate this seat from the assignment and create a user only one
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
    def staff_uncancel_pending!(staff_user)
      return unless seat_assignment.present?

      assignment = T.must(seat_assignment)

      case assignment.symbolized_assignable_type
      when :USER
        assignment.pending_cancellation_date = nil
        assignment.save!
      when :ORGANIZATION, :TEAM, :ORGANIZATION_INVITATION
        # need to disassociate this seat from the assignment and create a user only one
        Copilot::SeatAssignment.create!(
          owner_type: "Organization",
          owner_id: T.must(organization).id,
          organization: T.must(organization),
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
      billing_cycle_start_date = organization&.current_metered_billing_cycle_starts_at
      billing_cycle_end_date = organization&.next_metered_billing_cycle_starts_at

      # let's create one
      Copilot::SeatHistory.create!(
        seat: self,
        owner_id: owner_id,
        owner_type: owner_type,
        organization_id: organization_id,
        business: organization&.business,
        assigned_user: assigned_user,
        seat_created_at: T.must(created_at).to_date,
        billing_cycle_start_date: billing_cycle_start_date.present? ? billing_cycle_start_date.to_date : Date.new(9999, 12, 31),
        billing_cycle_end_date: billing_cycle_end_date.present? ? billing_cycle_end_date.to_date : Date.new(9999, 12, 31),
      )
    end

    sig { returns(T.nilable(Integer)) }
    def owner_id
      owner_id = organization&.id.to_i

      # if this seat assignment is an EnterpriseTeam level one, we should set the owner to business
      if seat_assignment.present? && T.must(seat_assignment).symbolized_assignable_type == :ENTERPRISE_TEAM
        enterprise_team = T.cast(T.must(seat_assignment).assignable, ::EnterpriseTeam)
        owner_id = enterprise_team.business_id
      end

      owner_id
    end

    sig { returns(String) }
    def owner_type
      owner_type = "Organization"

      # if this seat assignment is an EnterpriseTeam level one, we should set the owner to business
      if seat_assignment.present? && T.must(seat_assignment).symbolized_assignable_type == :ENTERPRISE_TEAM
        owner_type = "Business"
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
      @customer_id = if owner.is_a?(::Business)
        Copilot::Business.new(owner).customer_for&.id
      elsif owner.is_a?(::Organization)
        copilot_org.customer_for&.id
      end
    end

    sig { returns(Copilot::Organization) }
    memoize def copilot_org
      Copilot::Organization.new(T.must(organization))
    end

    # |                                      | BusinessTrial | Configuration | Organization | Business |
    # |--------------------------------------|---------------|---------------|--------------|----------|
    # | COPILOT_ENTERPRISE_TRIAL_SEAT        | ENTERPRISE    | BUSINESS      | REQUIRED     | REQUIRED |
    # | COPILOT_FOR_BUSINESS_TRIAL_SEAT      | BUSINESS      | BUSINESS      | REQUIRED     | OPTIONAL |
    # | COPILOT_STANDALONE_SEAT              | NONE          | BUSINESS      | NONE         | REQUIRED |
    # | COPILOT_ENTERPRISE_SEAT              | NONE          | ENTERPRISE    | REQUIRED     | REQUIRED |
    # | COPILOT_FOR_BUSINESS_SEAT            | NONE          | BUSINESS      | REQUIRED     | OPTIONAL |
    batch_method(:copilot_sku) do |seats|
      # load up the seat assignments and owners
      GitHub::PrefillAssociations.prefill_associations(seats, :seat_assignment)
      GitHub::PrefillAssociations.prefill_associations(seats.map(&:seat_assignment), :owner)

      # logically, this seats really is seat because this is an instance method, but i wrote it so you never know
      seats.index_with do |seat|
        case seat.seat_assignment.owner_type
        when "Organization"
          organization = seat.seat_assignment.owner

          GitHub::PrefillAssociations.prefill_associations(organization, :business)

          next :COPILOT_FOR_BUSINESS_BILLING_LOCKED if organization.disabled?

          next seat.seat_copilot_sku_for_org(organization) if Copilot::Organization.new(organization).feature_enabled?(:copilot_mixed_licenses)

          # If the user doesn't have a business, they can't be standalone OR have an enterprise copilot_plan.
          # Since they have a seat, they can't be individual.
          next :COPILOT_FOR_BUSINESS_SEAT unless seat.seat_assignment.owner.business.present?

          # they have a business, we can check the plan
          business = seat.seat_assignment.owner.business
          copilot_business = Copilot::Business.new(business)

          if copilot_business.copilot_plan_enterprise?
            # standalone seats are always BUSINESS
            # per Sean, you cannot be an enterprise plan AND have a trial.
            # so i'm gonna TRUST BY DEFAULT here
            :COPILOT_ENTERPRISE_SEAT
          else
            copilot_organization = Copilot::Organization.new(seat.seat_assignment.owner)

            if copilot_organization.has_trial?
              # they have a trial, so we need to check the plan of the trial
              # their business' copilot plan in configuration is probably set to business
              if T.must(copilot_organization.business_trial).copilot_plan_enterprise?
                :COPILOT_ENTERPRISE_TRIAL_SEAT
              else
                :COPILOT_FOR_BUSINESS_TRIAL_SEAT
              end
            else
              # no trial means full seat
              :COPILOT_FOR_BUSINESS_SEAT
            end
          end
        when "Business"
          # the seat (through the seat assignment) belongs to a business, so it's a standalone seat
          :COPILOT_STANDALONE_SEAT
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
        if T.must(copilot_org.business_trial).copilot_plan_enterprise?
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
