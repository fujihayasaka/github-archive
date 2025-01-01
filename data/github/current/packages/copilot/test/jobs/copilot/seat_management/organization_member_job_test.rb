# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::SeatManagement::OrganizationMemberJobTest < GitHub::TestCase
  include JobTestHelper
  include AuditLogHelpers
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub.flipper[:copilot_seat_assignment_job].enable
  end

  context "perform" do
    test "raises an error if the action is invalid" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      action = :invalid_action

      assert_raises(ArgumentError) do
        Copilot::SeatManagement::OrganizationMemberJob.perform_now(
          organization_id: organization.id,
          action: action,
          transaction_id: "1234",
          payload: { foo: "bar" },
          user_id: user.id,
        )
      end
    end

    test "queues another job if remove members" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      action = :remove_member
      Copilot::SeatManagement::OrganizationRemoveMemberJob.expects(:perform_later).once
      Copilot::SeatManagement::OrganizationMemberJob.perform_now(
        organization_id: organization.id,
        action: action,
        transaction_id: "1234",
        payload: { foo: "bar" },
        user_id: user.id,
      )
    end

    test "does nothing with fake org" do
      user = create(:user)
      action = :add_member

      logs = capture_logs do
        Copilot::ErrorReporter.expects(:report!).with do |error, context|
          error.is_a?(Copilot::Errors::CopilotError) &&
          context[:extra_details]["gh.organization.id"] == 233552342
        end
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationMemberJob.perform_now(
            organization_id: 233552342,
            action: action,
            transaction_id: "1234",
            payload: { foo: "bar" },
            user_id: user.id,
          )
        end
      end

      assert_match "Invalid Organization", logs
    end

    test "does nothing with a non-CFB org" do
      org = create(:credit_card_organization)
      user = create(:user)
      action = :add_member

      copilot_organization = Copilot::Organization.new(org)
      refute copilot_organization.copilot_for_business_enabled?

      Copilot::OrganizationCleaner.expects(:call).with(org.id, T.must(copilot_organization.customer_for).id).once
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationMemberJob.perform_now(
            organization_id: org.id,
            action: action,
            transaction_id: "1234",
            payload: { foo: "bar" },
            user_id: user.id,
          )
        end
      end

      assert_match "Organization not enabled for CFB", logs
    end

    test "cleans with fake user_id" do
      organization = create(:copilot_for_business_enabled_organization)
      create(:user)
      action = :add_member

      Copilot::UserCleaner.expects(:call).with(233552342).once
      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationMemberJob.perform_now(
            user_id: 233552342,
            organization_id: organization.id,
            action: action,
            transaction_id: "1234",
            payload: { foo: "bar" },
          )
        end
      end

      assert_match "Invalid User", logs
    end
  end

  context "add_member" do
    test "existing seat just returns" do
      seat = create(:copilot_seat)

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count } do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::SeatManagement::OrganizationMemberJob.perform_now(
              user_id: seat.assigned_user.id,
              organization_id: seat.organization.id,
              action: :add_member,
              transaction_id: "1234",
              payload: { foo: "bar" },
            )
          end
        end
      end

      assert_match "Existing Seat found for User", logs
    end

    test "organization seat assignment - auto assigns seat" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      assignment = create(:copilot_seat_assignment, organization: organization, assignable_id: organization.id, assignable_type: "Organization")

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later) do |org_id, user_id, seat|
        assert_equal organization.id, org_id
        assert_equal user.id, user_id
        assert_equal user.id, seat.assigned_user_id
      end.once

      logs = capture_logs do
        assert_changes -> { Copilot::Seat.count } do
          assert_changes -> { Copilot::SeatHistory.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationMemberJob.perform_now(
                user_id: user.id,
                organization_id: organization.id,
                action: :add_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      assert_match "Organization SeatAssignment found", logs
      assert assignment.seats.count == 1
    end

    test "organization seat assignment without owner - populates owner and owner_type on seat assignment" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      assignment = create(:copilot_seat_assignment, organization: organization, assignable_id: organization.id, assignable_type: "Organization")
      assignment.update_columns(owner_id: nil, owner_type: nil)

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later) do |org_id, user_id, seat|
        assert_equal organization.id, org_id
        assert_equal user.id, user_id
        assert_equal user.id, seat.assigned_user_id
      end.once

      logs = capture_logs do
        assert_changes -> { Copilot::Seat.count } do
          assert_changes -> { Copilot::SeatHistory.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationMemberJob.perform_now(
                user_id: user.id,
                organization_id: organization.id,
                action: :add_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
            assignment.reload
            assert_equal organization.id, assignment.owner_id
            assert_equal "Organization", assignment.owner_type
          end
        end
      end

      assert_match "Organization SeatAssignment found", logs
      assert assignment.seats.count == 1
    end

    test "organization seat assignment - but not yet an org member?" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)
      assignment = create(:copilot_seat_assignment, organization: organization, assignable_id: organization.id, assignable_type: "Organization")

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never

      Copilot::SeatAssignment.any_instance.expects(:includes_user?).returns(false).twice

      logs = capture_logs do
        assert_no_changes -> { Copilot::Seat.count } do
          assert_no_changes -> { Copilot::SeatHistory.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationMemberJob.perform_now(
                user_id: user.id,
                organization_id: organization.id,
                action: :add_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      assert_match "Organization SeatAssignment found", logs
      assert assignment.seats.count == 0
    end

    test "invitation seat assignment - auto assigns seat" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      copilot_organization = Copilot::Organization.new(organization)
      result = copilot_organization.assign([user], organization.admins.first)

      assignment = result.value!.first
      invitation = assignment.assignable
      invitation.accept

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later) do |org_id, user_id, seat|
        assert_equal organization.id, org_id
        assert_equal user.id, user_id
        assert_equal user.id, seat.assigned_user_id
      end.once

      logs = capture_logs do
        assert_changes -> { Copilot::Seat.count } do
          assert_changes -> { Copilot::SeatHistory.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationMemberJob.perform_now(
                user_id: user.id,
                organization_id: organization.id,
                action: :add_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      assert_match "No existing seat found for User", logs
      assert_match "OrganizationInvitation SeatAssignment(s) found, creating Seat", logs
      assert_match "No Organization SeatAssignment found", logs

      assert_equal 1, assignment.seats.count
      assert_equal user, assignment.reload.assignable
    end

    test "invitation seat assignment with CFI - auto assigns seat and cancels cfi" do
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)

      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: copilot_monthly_product_uuid,
        free_trial_ends_on: 10.days.from_now
      )

      organization = create(:copilot_for_business_enabled_organization)
      copilot_organization = Copilot::Organization.new(organization)
      result = copilot_organization.assign([user], organization.admins.first)

      assignment = result.value!.first
      invitation = assignment.assignable
      invitation.accept

      logs = capture_logs do
        assert_changes -> { Copilot::Seat.count } do
          perform_enqueued_jobs(only: Copilot::SeatManagement::SeatAssignedJob) do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationMemberJob.perform_now(
                user_id: user.id,
                organization_id: organization.id,
                action: :add_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      assert_match "No existing seat found for User", logs
      assert_match "OrganizationInvitation SeatAssignment(s) found, creating Seat", logs
      assert_match "No Organization SeatAssignment found", logs
      assert_match "Cancelling and refunding", logs

      assert_equal 1, assignment.seats.count
      assert_equal user, assignment.reload.assignable
    end

    test "email invitation seat assignment - auto assigns seat" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      user.emails.map(&:verify!)
      copilot_organization = Copilot::Organization.new(organization)
      result = copilot_organization.assign([user.email], organization.admins.first)

      assignment = result.value!.first
      invitation = assignment.assignable
      invitation.accept

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later) do |org_id, user_id, seat|
        assert_equal organization.id, org_id
        assert_equal user.id, user_id
        assert_equal user.id, seat.assigned_user_id
      end.once

      logs = capture_logs do
        assert_changes -> { Copilot::Seat.count } do
          assert_changes -> { Copilot::SeatHistory.count } do
            ActiveRecord::Base.connected_to(role: :reading) do
              Copilot::SeatManagement::OrganizationMemberJob.perform_now(
                user_id: user.id,
                organization_id: organization.id,
                action: :add_member,
                transaction_id: "1234",
                payload: { foo: "bar" },
              )
            end
          end
        end
      end

      assert_match "No existing seat found for User", logs
      assert_match "Found invitations for this organization for User", logs
      assert_match "OrganizationInvitation SeatAssignment(s) found, creating Seat", logs
      assert_match "No Organization SeatAssignment found", logs

      assert_equal 1, assignment.seats.count
      assert_equal user, assignment.reload.assignable
    end

    test "no organization seat assignment - no change" do
      organization = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      organization.add_member(user)

      Copilot::SeatManagement::SeatAssignedJob.expects(:perform_later).never
      assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count } do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrganizationMemberJob.perform_now(
            user_id: user.id,
            organization_id: organization.id,
            action: :add_member,
            transaction_id: "1234",
            payload: { foo: "bar" },
          )
        end
      end
    end

    test "invitation seat assignment - starts a Copilot Business trial when it is pending" do
      trial = create(:copilot_business_trial, :organization, state: :pending)
      org = trial.trialable
      admin_user = org.admins.first
      invitee = create(:user)

      copilot_organization = Copilot::Organization.new(org)
      copilot_organization.enable_copilot!

      result = copilot_organization.assign([invitee.email], admin_user)
      assignment = result.value!.first

      invitation = assignment.assignable

      perform_enqueued_jobs(only: [Copilot::SeatManagement::OrganizationMemberJob]) do
        invitation.accept
      end

      assert_equal(trial.reload.state, "recently_started")
    end

    test "invitation seat assignment - starts a Copilot Enterprise trial when it is pending and copilot_for_dotcom is enabled" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      org = create(:copilot_for_business_enabled_organization)
      trial = create(:copilot_business_trial, :organization,
        copilot_plan: "enterprise",
        state: "pending",
        trialable: org,
      )
      admin_user = org.admins.first
      invitee = create(:user)

      copilot_organization = Copilot::Organization.new(org)

      result = copilot_organization.assign([invitee.email], admin_user)
      assignment = result.value!.first

      invitation = assignment.assignable

      # Doing this instead of calling copilot_org.copilot_for_dotcom_enabled! since that would now trigger starting the CE trial
      copilot_config = Copilot::Configuration.find_by(configurable_type: "Organization", configurable_id: org.id)
      T.must(copilot_config).update(github_enterprise_feature_group: "enabled")

      assert Copilot::Organization.new(org).copilot_for_dotcom_enabled?

      perform_enqueued_jobs(only: [Copilot::SeatManagement::OrganizationMemberJob]) do
        invitation.accept
      end

      assert_equal(trial.reload.state, "recently_started")
    end
  end

  context "restore_member" do
    test "no organization seat assignment does nothing" do
      actor = create(:user)
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      restorable_organization_user = setup_restorable_user(user: user, org: org)

      with_es_refresh do
        assert_performed_jobs 2, only: Copilot::SeatManagement::OrganizationMemberJob do
          logs = capture_logs do
            assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count } do
              restorable_organization_user.restore(actor: actor)
            end
          end
          assert_match "No Organization/OrganizationInvitation SeatAssignment found", logs
        end
      end
    end

    test "organization seat assignment with existing seat does nothing" do
      actor = create(:user)
      org = create(:copilot_for_business_enabled_organization)
      assignment = create(:copilot_seat_assignment, organization: org, assignable_id: org.id, assignable_type: "Organization")
      user = create(:user)
      org.add_member(user)
      assignment.convert_to_seats
      restorable_organization_user = setup_restorable_user(user: user, org: org)

      org.remove_member(user)

      with_es_refresh do
        assert_performed_jobs 1, only: Copilot::SeatManagement::OrganizationMemberJob do
          logs = capture_logs do
            assert_no_changes -> { Copilot::Seat.count + Copilot::SeatHistory.count } do
              restorable_organization_user.restore(actor: actor)
            end
          end
          assert_match "Existing Seat found for User", logs
        end
      end
    end

    test "organization seat assignment without seat creates new one" do
      actor = create(:user)
      org = create(:copilot_for_business_enabled_organization)
      assignment = create(:copilot_seat_assignment, organization: org, assignable_id: org.id, assignable_type: "Organization")
      user = create(:user)
      assignment.convert_to_seats
      restorable_organization_user = setup_restorable_user(user: user, org: org)

      org.remove_member(user)

      with_es_refresh do
        assert_performed_jobs 2, only: Copilot::SeatManagement::OrganizationMemberJob do
          logs = capture_logs do
            assert_changes -> { Copilot::Seat.count }, 1 do
              assert_changes -> { Copilot::SeatHistory.count }, 1 do
                restorable_organization_user.restore(actor: actor)
              end
            end
          end
          assert_match "Existing Seat found for User", logs
        end
      end
    end

    test "deletes old seat assignments and seats for users who are reinstated" do
      actor = create(:user)
      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      org.add_member(user)
      Copilot::Organization.new(org).seat_management_allow_all!
      restorable_organization_user = setup_restorable_user(user: user, org: org)

      org.remove_member(user)
      assignment_pending_removal = create(:copilot_seat_assignment, organization: org, assignable: user, pending_cancellation_date: 1.month.from_now)
      seat_pending_removal = create(:copilot_seat, seat_assignment: assignment_pending_removal, organization: org, assigned_user: user)

      with_es_refresh do
        assert_performed_jobs 1, only: Copilot::SeatManagement::OrganizationMemberJob do
          logs = capture_logs do
            restorable_organization_user.restore(actor: actor)
          end
          assert_match "User reinstated to organization with allow all setting", logs
          assert_raises(ActiveRecord::RecordNotFound) { assignment_pending_removal.reload }
          assert_raises(ActiveRecord::RecordNotFound) { seat_pending_removal.reload }
        end
      end
    end
  end

  sig { params(user: User, org: Organization).returns(Restorable::OrganizationUser) }
  def setup_restorable_user(user:, org:)
    restorable = Restorable.create

    restorable.memberships.create({
      subject_type: "Organization",
      subject_id: org.id,
      action: :read,
    })

    restorable_organization_user = Restorable::OrganizationUser.create({
      restorable: restorable,
      organization: org,
      user: user,
    })

    restorable_organization_user.save_memberships_complete
    restorable_organization_user.save_issue_assignments_complete
    restorable_organization_user.save_repositories_complete
    restorable_organization_user.save_watched_repositories_complete
    restorable_organization_user.save_repository_stars_complete
    restorable_organization_user.save_custom_email_routings_complete

    restorable_organization_user
  end
end if GitHub.copilot_enabled?
