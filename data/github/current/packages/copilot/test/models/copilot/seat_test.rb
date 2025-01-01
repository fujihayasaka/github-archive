# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotSeatTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include DogstatsTestHelpers
  include HydroTestHelpers

  context "validation" do
    test "factory" do
      seat = build(:copilot_seat)
      assert seat.valid?
    end

    test "requires unique seat assignment - user" do
      seat = build(:copilot_seat)
      assert seat.valid?
      seat.save!

      seat = build(:copilot_seat, organization: seat.organization, seat_assignment: seat.seat_assignment, assigned_user: seat.assigned_user)
      refute seat.valid?
    end

    test "requires an organization" do
      organization = create(:copilot_for_business_enabled_organization)

      seat = Copilot::Seat.new
      refute seat.valid?
      refute_nil seat.errors[:organization]

      seat.organization = organization
      refute seat.valid?
      assert_equal [], seat.errors[:organization]
    end

    test "requires an assigned user belonging to the organization" do
      user = create(:user)
      organization = create(:copilot_for_business_enabled_organization)

      seat = Copilot::Seat.new
      seat.assigned_user = user
      seat.organization = organization

      refute seat.valid?
      refute_nil seat.errors[:assigned_user]

      organization.add_member(user)

      refute seat.valid? # need to call this to get the errors to update
      assert_equal [], seat.errors[:assigned_user]
    end

    test "requires user seat assignment belonging to the organization" do
      user = create(:user)
      organization = create(:copilot_for_business_enabled_organization)

      seat = Copilot::Seat.new
      organization.add_member(user)
      seat.assigned_user = user
      seat.organization = organization

      refute seat.valid? # need to call this to get the errors to update
      refute_nil seat.errors[:seat_assignment]

      seat.seat_assignment = create(:copilot_seat_assignment, :user, organization: organization, assignable: user)
      assert seat.valid?
    end

    test "requires team seat assignment belonging to the organization" do
      user = create(:user)
      organization = create(:copilot_for_business_enabled_organization)
      team = create(:team, organization: organization)
      team.add_member(user)

      seat = Copilot::Seat.new
      organization.add_member(user)
      seat.assigned_user = user
      seat.organization = organization

      refute seat.valid? # need to call this to get the errors to update
      refute_nil seat.errors[:seat_assignment]

      seat.seat_assignment = create(:copilot_seat_assignment, :team, organization: organization, assignable: create(:team, organization: organization))
      refute seat.valid? # need to call this to get the errors to update
      refute_nil seat.errors[:assigned_user]
      assert_equal [], seat.errors[:seat_assignment]

      seat.seat_assignment = create(:copilot_seat_assignment, :team, organization: organization, assignable: team)
      assert seat.valid?
    end

    test "requires organization invitation seat assignment belonging to the organization" do
      user = create(:user)
      organization = create(:copilot_for_business_enabled_organization)

      seat = Copilot::Seat.new
      seat.assigned_user = user
      seat.organization = organization

      organization_invitation = create(:organization_invitation, organization: organization, invitee: user)
      seat.seat_assignment = create(:copilot_seat_assignment, :organization_invitation, organization: organization, assignable: organization_invitation)
      assert seat.valid?
    end
  end

  context "assigned_user_belongs_to_owner" do
    test "adds no errors if the seat_assignment is nil" do
      seat = build(:copilot_seat, seat_assignment: nil)
      seat.assigned_user_belongs_to_owner
      assert_equal [], seat.errors[:seat_assignment]
    end

    test "adds errors if the seat assignment assignable is nil for some reason" do
      # why would this happen? i don't know but you should feel bad if it does
      seat = build(:copilot_seat)
      seat.seat_assignment.assignable = nil
      Copilot::ErrorReporter.expects(:report!).once
      seat.assigned_user_belongs_to_owner
      assert_equal ["has no assignable"], seat.errors[:seat_assignment]
    end

    test "adds errors if the assigned user doesn't belong to the enterprise_team" do
      seat = build(:copilot_seat, seat_assignment: build(:copilot_seat_assignment, :enterprise_team))
      seat.assigned_user = create(:user)
      seat.assigned_user_belongs_to_owner
      assert_equal ["must belong to the same owner as the seat assignment"], seat.errors[:assigned_user]
    end

    test "adds errors if the assigned user doesn't belong to the organization" do
      seat = build(:copilot_seat, seat_assignment: build(:copilot_seat_assignment, :organization))
      seat.assigned_user = create(:user)
      seat.assigned_user_belongs_to_owner
      assert_equal ["must belong to the same owner as the seat assignment"], seat.errors[:assigned_user]
    end

    test "adds errors if the assigned user doesn't belong to the team" do
      seat = build(:copilot_seat, seat_assignment: build(:copilot_seat_assignment, :team))
      seat.assigned_user = create(:user)
      seat.assigned_user_belongs_to_owner
      assert_equal ["must belong to the same owner as the seat assignment"], seat.errors[:assigned_user]
    end

    test "adds an error if the user in the seat assignment does not belong to the owner" do
    end
  end

  context "cancel!" do
    test "sends email, creates notification, destroys, and updates the seat history" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)

      seat = create(
        :copilot_seat,
        organization: organization,
        assigned_user: user,
      )
      assert_equal 1, Copilot::SeatHistory.count
      seat.reload
      history = seat.seat_history
      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:seat_removed_for_user)
        .with(organization, user)
        .returns(mailer)
        .once

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_cancelled).with(
        seat,
        nil,
        false,
        :cancel_immediately,
        trial_seat: false,
      ).once
      assert_nil history.seat_deleted_at
      assert_changes -> { Copilot::EditorNotification.count }, from: 0, to: 1 do
        seat.cancel!
      end
      assert_equal history.reload.seat_deleted_at, Date.current

      refute Copilot::Seat.exists?(seat.id)
    end

    test "sends email, creates notification, destroys, and updates the seat history when cancelled by staff" do
      organization = create(:organization)
      user = create(:user)
      organization.add_member(user)
      staff = create :staff_admin_user

      seat = create(
        :copilot_seat,
        organization: organization,
        assigned_user: user,
      )
      assert_equal 1, Copilot::SeatHistory.count
      seat.reload
      history = seat.seat_history
      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:seat_removed_for_user)
        .with(organization, user)
        .returns(mailer)
        .once

      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_cancelled).with(
        seat,
        staff,
        true,
        :cancel_immediately,
        trial_seat: false,
      ).once
      assert_nil history.seat_deleted_at
      assert_changes -> { Copilot::EditorNotification.count }, from: 0, to: 1 do
        seat.cancel!(actor: staff, staff_cancel: true)
      end
      assert_equal history.reload.seat_deleted_at, Date.current

      refute Copilot::Seat.exists?(seat.id)
    end

    test "updates existing notification if it exists" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)

      seat = create(
        :copilot_seat,
        organization: organization,
        assigned_user: user,
      )
      assert_equal 1, Copilot::SeatHistory.count
      seat.reload
      history = seat.seat_history
      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:seat_removed_for_user)
        .with(organization, user)
        .returns(mailer)
        .once

      Copilot::ErrorReporter.expects(:report!).never
      Copilot::Instrumenter.expects(:instrument_copilot_for_business_seat_cancelled).with(
        seat,
        nil,
        false,
        :cancel_immediately,
        trial_seat: false,
      ).once
      assert_nil history.seat_deleted_at

      Copilot::EditorNotification.create(
        user: seat.assigned_user,
        notification_id: "copilot_seat_removed_#{seat.organization_id}",
      )

      assert_no_changes -> { Copilot::EditorNotification.count } do
        seat.cancel!
      end
      assert_equal history.reload.seat_deleted_at, Date.current

      refute Copilot::Seat.exists?(seat.id)
    end

    test "works when the org has been deleted" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)

      seat = create(
        :copilot_seat,
        organization: organization,
        assigned_user: user,
      )
      assert_equal 1, Copilot::SeatHistory.count

      co = Copilot::Organization.new(organization)
      customer_id = T.must(co.customer_for).id
      seat.reload

      history = seat.seat_history
      organization.destroy!
      seat.reload
      seat.customer_id = customer_id
      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:seat_removed_for_user)
        .with(nil, user)
        .returns(mailer)
        .once

      assert_nil history.seat_deleted_at

      assert_changes -> { Copilot::EditorNotification.count }, from: 0, to: 1 do
        seat.cancel!
      end
      refute Copilot::Seat.exists?(seat.id)
      assert_equal history.reload.seat_deleted_at, Date.current
    end

    test "sends the correct email and notification when it's a trial seat" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)

      seat = create(
        :copilot_seat,
        organization: organization,
        assigned_user: user,
      )

      mailer = mock
      mailer.stubs(:deliver_later)
      CopilotForBusinessMailer.expects(:trial_seat_expired_for_user).with(organization, user).returns(mailer).once
      assert_changes -> { Copilot::EditorNotification.count }, from: 0, to: 1 do
        seat.cancel!(trial_seat: true)
      end
    end

    test "immediately deletes the underlying seat assignment for a user" do
      seat = create(:copilot_seat)

      assert_changes -> { Copilot::SeatAssignment.count }, from: 1, to: 0 do
        seat.cancel!
      end
    end

    test "does not delete underlying seat assignment for a team" do
      seat = create(:copilot_seat, :team)

      assert_no_changes -> { Copilot::SeatAssignment.count } do
        seat.cancel!
      end
    end

    test "does not delete underlying seat assignment for an organization" do
      seat = create(:copilot_seat, :organization)

      assert_no_changes -> { Copilot::SeatAssignment.count } do
        seat.cancel!
      end
    end
  end

  context "billing platform hydro messages" do
    context "message format" do
      test "organization prorated seat emission" do
        org = create(:copilot_for_business_enabled_organization)
        seat = create(:copilot_seat, organization: org)
        customer = org.customer_for(Customer::DEFAULT_PURPOSE, delegate_to_business: true)
        user = seat.assigned_user
        message = seat.prorated_billing_message(quantity: 0.5, sku: "copilot_for_business")
        assert_equal message[:sku], "copilot_for_business"
        assert_equal message[:quantity], 0.5
        assert_equal message[:entity], { customer_id: customer.id, organization_id: org.id, actor_id: user.id }
        assert_equal message[:source_uri], GlobalID.create(org).to_s
      end

      test "organization prorated seat emission with the right sku" do
        org = create(:copilot_for_business_enabled_organization)
        Copilot::Business.new(org.business).copilot_plan_enterprise!
        seat = create(:copilot_seat, organization: org)
        message = seat.prorated_billing_message(quantity: 0.5, sku: "copilot_enterprise")
        assert_equal message[:sku], "copilot_enterprise"
      end
    end

    context "#seat_prorated_billing_message_emission" do
      test "sends message when the feature flag is on" do
        seat = create(:copilot_seat)
        create(:billing_platform_enabled_product, customer: seat.organization.billable_owner.customer, copilot: true)

        seat.seat_prorated_billing_message_emission(quantity: 0.5, sku: "copilot_for_business")
        assert_hydro_messages(schema: "billingplatform.v1.Usage", count: 1)
      end

      test "does not send message when the organization does not have a customer" do
        org = create(:organization)
        Copilot::Organization.new(org).enable_copilot!
        customer = Copilot::Organization.new(org).customer_for
        assert_nil(customer)
        seat = create(:copilot_seat, organization: org)

        seat.seat_prorated_billing_message_emission(quantity: 0.5, sku: "copilot_for_business")
        refute_hydro_messages(schema: "billingplatform.v1.Usage")
      end

      test "message sent when the organization does not have a customer but the customer_id is set on the seat" do
        bpep = create(:billing_platform_enabled_product, copilot: true)

        org = create(:organization)
        Copilot::Organization.new(org).enable_copilot!
        customer = Copilot::Organization.new(org).customer_for
        assert_nil(customer)
        seat = build(:copilot_seat, organization: org)
        seat.customer_id = bpep.customer_id
        seat.save

        seat.seat_prorated_billing_message_emission(quantity: 0.5, sku: "copilot_for_business")
        assert_hydro_messages(schema: "billingplatform.v1.Usage", count: 1)
      end

      test "sends message with the right SKU" do
        seat = create(:copilot_seat)
        create(:billing_platform_enabled_product, customer: seat.organization.billable_owner.customer, copilot: true)

        seat.seat_prorated_billing_message_emission(quantity: 0.5, sku: "copilot_enterprise")
        message = {
          sku: "copilot_enterprise",
          quantity: 0.5,
          entity: {
            customer_id: seat.organization.customer_for(Customer::DEFAULT_PURPOSE, delegate_to_business: true).id,
            actor_id: seat.assigned_user.id,
            organization_id: seat.organization.id,
          },
        }
        assert_hydro_published_partial(message, schema: "billingplatform.v1.Usage")
        assert_hydro_messages(schema: "billingplatform.v1.Usage", count: 1)
      end

      test "generates unique usage_uuids for each run" do
        seat = create(:copilot_seat)
        create(:billing_platform_enabled_product, customer: seat.organization.billable_owner.customer, copilot: true)

        Timecop.travel(Date.current.beginning_of_day) do
          emission = seat.prorated_billing_message(quantity: 0.5, sku: "copilot_for_business")
          Timecop.travel(1.minute)
          next_emission = seat.prorated_billing_message(quantity: 0.5, sku: "copilot_for_business")
          assert_equal emission[:usage_uuid], next_emission[:usage_uuid]
          Timecop.travel(1.day)
          final_emission = seat.prorated_billing_message(quantity: 0.5, sku: "copilot_for_business")
          refute_equal emission[:usage_uuid], final_emission[:usage_uuid]
        end
      end
    end
  end

  context "generate_seat_history!" do
    test "stores on create" do
      assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team = assignment.assignable

      seat = assert_changes -> { Copilot::SeatHistory.count }, from: 0, to: 1 do
        Copilot::Seat.create!(
          assigned_user_id: enterprise_team.member_user_ids.last,
          seat_assignment: assignment,
        )
      end
      seat_history = Copilot::SeatHistory.last
      assert_equal seat_history.seat_id, seat.id
      assert_equal seat_history.owner_id, enterprise_team.business.id
    end

    test "stores on create for an enterprise team, as one does" do
      seat = assert_changes -> { Copilot::SeatHistory.count }, from: 0, to: 1 do
        create(:copilot_seat)
      end
      seat_history = Copilot::SeatHistory.last
      assert_equal seat_history.seat_id, seat.id
      assert_equal seat_history.owner_id, seat.organization.id
    end

    test "safely exits early when a history already exists" do
      seat = create(:copilot_seat)
      seat.reload
      assert seat.seat_history

      assert_no_changes -> { Copilot::SeatHistory.count } do
        seat.generate_seat_history!
      end
      assert_dogstats_increment 1, "copilot.seat_history_job.seat_history_found"
    end
  end

  context "history_deletion" do
    test "stores on destroy" do
      seat = create(:copilot_seat)
      seat.reload
      history = seat.seat_history
      assert_nil history.seat_deleted_at
      seat.cancel!

      assert_equal history.reload.seat_deleted_at, Date.current
    end
  end

  context "for_assigned_user_and_owner" do
    test "returns the seat for the assignable and owner" do
      seat = create(:copilot_seat)
      assert_equal Array.wrap(seat), Copilot::Seat.for_assigned_user_and_owner(seat.seat_assignment.assignable, seat.organization)
    end

    test "returns a bunch of seats for an organization seat assignment" do
      seat_assignment = create(:copilot_seat_assignment, :organization)
      organization = seat_assignment.assignable

      10.times do
        user = create(:user)
        organization.add_member(user)
      end

      seat_assignment.convert_to_seats

      assert_equal organization.member_ids.count, Copilot::Seat.for_assigned_user_and_owner(organization.member_ids, organization).count
    end

    test "returns seats for enterpriseteam" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team, member_count: 10)
      enterprise_team = seat_assignment.assignable
      seat_assignment.convert_to_seats

      assert_equal enterprise_team.member_user_ids.count, Copilot::Seat.for_assigned_user_and_owner(enterprise_team.member_user_ids, enterprise_team.business).count
    end
  end

  context "batch_methods" do
    context "copilot_sku" do
      test "gets business by default" do
        seat = create(:copilot_seat)
        assert_equal :COPILOT_FOR_BUSINESS_SEAT, seat.copilot_sku
      end

      test "gets enterprise when passed" do
        seat = create(:copilot_seat, copilot_plan: "enterprise")
        assert_equal :COPILOT_ENTERPRISE_SEAT, seat.copilot_sku
      end

      test "gets standalone for an enterprise team" do
        seat = create(:copilot_seat, :enterprise_team_member)
        assert_equal :COPILOT_STANDALONE_SEAT, seat.copilot_sku
      end

      test "gets enterprise_trial for an enterprise trial" do
        organization = create(:copilot_for_business_credit_card_enabled_organization)
        create(:billing_sales_serve_plan_subscription, customer: organization.business.customer)
        trial = create(:copilot_business_trial, trialable_type: "Organization", trialable_id: organization.id, copilot_plan: "enterprise")
        organization = trial.trialable
        seat = create(:copilot_seat, organization: organization)
        assert_equal :COPILOT_ENTERPRISE_TRIAL_SEAT, seat.copilot_sku
      end

      test "gets business trial for a business trial" do
        organization = create(:copilot_for_business_credit_card_enabled_organization)
        create(:billing_sales_serve_plan_subscription, customer: organization.business.customer)
        trial = create(:copilot_business_trial, trialable_type: "Organization", trialable_id: organization.id)
        organization = trial.trialable
        seat = create(:copilot_seat, organization: organization)
        assert_equal :COPILOT_FOR_BUSINESS_TRIAL_SEAT, seat.copilot_sku
      end

      test "sends an error" do
        seat = create(:copilot_seat)
        assignment = seat.seat_assignment
        assignment.stubs(:owner_type).returns("potato")
        assert_raises(Copilot::Errors::SeatAssignmentError) do
          seat.copilot_sku
        end
      end

      context "with mixed licences enabled" do
        test "returns business sku when org plan is business" do
          GitHub.flipper[:copilot_mixed_licenses].enable

          seat = create(:copilot_seat)
          org = seat.seat_assignment.owner

          Copilot::Business.new(org.business).copilot_plan_enterprise!
          Copilot::Organization.new(org).copilot_plan_business!

          assert_equal :COPILOT_FOR_BUSINESS_SEAT, seat.copilot_sku
        end

        test "returns enterprise sku when org plan is enterprise" do
          GitHub.flipper[:copilot_mixed_licenses].enable

          seat = create(:copilot_seat)
          org = seat.seat_assignment.owner

          Copilot::Business.new(org.business).copilot_plan_business!
          Copilot::Organization.new(org).copilot_plan_enterprise!

          assert_equal :COPILOT_ENTERPRISE_SEAT, seat.copilot_sku
        end

        test "returns enterprise trial sku when org trial is enterprise" do
          organization = create(:copilot_for_business_credit_card_enabled_organization)
          create(:billing_sales_serve_plan_subscription, customer: organization.business.customer)
          trial = create(:copilot_business_trial, trialable_type: "Organization", trialable_id: organization.id)
          organization = trial.trialable
          seat = create(:copilot_seat, organization: organization)

          assert_equal :COPILOT_FOR_BUSINESS_TRIAL_SEAT, seat.copilot_sku

          trial.cancel!
          trial.convert_trial!(create(:user), new_trial_length: 30, new_copilot_plan: "enterprise")

          seat = create(:copilot_seat, organization: organization)
          assert_equal :COPILOT_ENTERPRISE_TRIAL_SEAT, seat.copilot_sku
        end
      end
    end
  end

  context "for_business" do
    context "when passing a standard business with orgs" do
      test "returns seats for the orgs" do
        business = create(:business)
        org = create(:organization, business: business)
        seat = create(:copilot_seat, organization: org)

        assert_equal [seat], Copilot::Seat.for_business(business)
      end
    end

    context "when passing a standalone business" do
      test "returns seats for the business" do
        business = create(:business, :enterprise_managed_business, seats_plan_type: :basic)
        enterprise_team = create(:copilot_enterprise_team, business: business)
        standalone_seat_assignment = create(:copilot_seat_assignment, :enterprise_team, assignable: enterprise_team, owner: business)
        seat = create(:copilot_seat, seat_assignment: standalone_seat_assignment, assigned_user_id: enterprise_team.member_user_ids.first)

        assert_equal [seat], Copilot::Seat.for_business(business)
      end
    end

    context "#staff_cancel_pending!" do
      test "works when a user is suspended" do
        staff_user = create(:user)

        org = create(:organization)
        good_user = create(:user)
        bad_user = create(:user)

        org.add_member(good_user)
        org.add_member(bad_user)

        assignment = create(:copilot_seat_assignment, :organization, assignable: org, owner: org, assigning_user: org.admins.first)
        assignment.convert_to_seats

        suspended_seat = assignment.seats.find { |s| s.assigned_user_id == bad_user.id }
        bad_user.suspend("bad user")

        Copilot::Instrumenter
          .expects(:instrument_copilot_for_business_seat_cancelled)
          .once
          .with(suspended_seat, staff_user, true, :cancel_immediately, trial_seat: false)

        assert_changes -> { Copilot::Seat.count }, from: 3, to: 2 do
          assert_no_changes -> { Copilot::SeatAssignment.count } do
            suspended_seat.staff_cancel_pending!(staff_user)
          end
        end
      end
    end
  end
end if GitHub.copilot_enabled?
