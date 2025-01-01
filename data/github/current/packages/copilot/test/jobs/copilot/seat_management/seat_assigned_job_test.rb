# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"
require "test_helpers/missing_record_helper"

class Copilot::SeatManagement::SeatAssignedJobTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include GitHub::LoggerHelper
  include JobTestHelper
  include MissingRecordHelper
  include HydroTestHelpers

  setup do
    GitHub.flipper[:copilot_seat_assignment_job].enable
  end

  test "no org" do
    org = missing(:organization)
    user = create(:user)

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(org.id, user.id)
      end
    end
    assert_match "Invalid Organization", logs
  end

  test "no user" do
    organization = create(:copilot_for_business_enabled_organization)
    user = missing(:user)

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
      end
    end
    assert_match "Invalid User", logs
  end

  test "no seat" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    organization.add_member(user)

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
      end
    end
    assert_match "Missing Seat", logs
  end

  test "notifies the user that they have been assigned a paid seat" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    organization.add_member(user)

    create(:copilot_seat, organization: organization, assigned_user: user)

    mailer = mock
    mailer.stubs(:deliver_later)

    CopilotForBusinessMailer.expects(:seat_added_for_user).with(organization, user).returns(mailer).once
    CopilotForBusinessMailer.expects(:trial_seat_added_for_user).never
    CopilotEnterpriseMailer.expects(:trial_seat_added_for_user).never
    CopilotEnterpriseMailer.expects(:welcome_individual).never

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
      end
    end

    assert_match "Deleting any FreeUser records", logs
  end

  test "notifies the user that they have been assigned a paid seat under a copilot enterprise plan" do
    organization = create(:copilot_enterprise_enabled_organization)
    user = create(:user)
    organization.add_member(user)

    create(:copilot_seat, organization: organization, assigned_user: user)

    mailer = mock
    mailer.stubs(:deliver_later)

    CopilotEnterpriseMailer.expects(:welcome_individual).with(organization, user).returns(mailer).once
    CopilotForBusinessMailer.expects(:seat_added_for_user).never
    CopilotForBusinessMailer.expects(:trial_seat_added_for_user).never
    CopilotEnterpriseMailer.expects(:trial_seat_added_for_user).never

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
      end
    end

    assert_match "Deleting any FreeUser records", logs
  end

  test "notifies the user that they have been assigned a paid seat under a copilot enterprise plan with direct org license" do
    GitHub.flipper[:copilot_mixed_licenses].enable

    business = create(:business)
    org = create(:organization, business: business)
    cp_biz = Copilot::Business.new(business)
    cp_biz.enable_copilot_for_all_organizations!
    cp_biz.copilot_plan_business!
    copilot_org = Copilot::Organization.new(org)
    copilot_org.enable_copilot!
    copilot_org.copilot_plan_enterprise!

    user = create(:user)
    org.add_member(user)

    create(:copilot_seat, organization: org, assigned_user: user)

    mailer = mock
    mailer.stubs(:deliver_later)

    # We expect the enterprise mailer to be called, the org has it's own
    # "enterprise" plan, even though the parent has a plan type of "business"
    CopilotEnterpriseMailer.expects(:welcome_individual).with(org, user).returns(mailer).once

    ActiveRecord::Base.connected_to(role: :reading) do
      Copilot::SeatManagement::SeatAssignedJob.perform_now(org.id, user.id)
    end
  end

  test "notifies the user that they have been assigned a paid seat under a copilot business plan with direct org license" do
    GitHub.flipper[:copilot_mixed_licenses].enable

    business = create(:business)
    org = create(:organization, business: business)
    cp_biz = Copilot::Business.new(business)
    cp_biz.enable_copilot_for_all_organizations!
    cp_biz.copilot_plan_enterprise!
    copilot_org = Copilot::Organization.new(org)
    copilot_org.enable_copilot!
    copilot_org.copilot_plan_business!

    user = create(:user)
    org.add_member(user)

    create(:copilot_seat, organization: org, assigned_user: user)

    mailer = mock
    mailer.stubs(:deliver_later)

    # We expect the business mailer to be called, the org has it's own
    # "business" plan, even though the parent has a plan type of "enterprise"
    CopilotForBusinessMailer.expects(:seat_added_for_user).with(org, user).returns(mailer).once

    ActiveRecord::Base.connected_to(role: :reading) do
      Copilot::SeatManagement::SeatAssignedJob.perform_now(org.id, user.id)
    end
  end

  test "creates a SeatHistory record if one doesn't exist" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    organization.add_member(user)

    create(:copilot_seat, organization: organization, assigned_user: user)
    # since the factory above creates a SeatHistory, we need to delete them all
    Copilot::SeatHistory.delete_all
    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
      end
    end

    assert_match "Deleting any FreeUser records", logs
    assert_equal 1, Copilot::SeatHistory.count
  end

  test "doesn't create a SeatHistory record if one exists" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    organization.add_member(user)

    create(:copilot_seat, organization: organization, assigned_user: user)

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
      end
    end

    assert_match "Deleting any FreeUser records", logs
    assert_equal 1, Copilot::SeatHistory.count
  end

  test "notifies the user that they have been assigned a Copilot Business trial seat" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    trial = create(:copilot_business_trial, :organization, trialable: organization, state: :recently_started)
    organization.add_member(user)
    create(:copilot_seat, organization: organization, assigned_user: user)

    mailer = mock
    mailer.stubs(:deliver_later)

    CopilotForBusinessMailer.expects(:trial_seat_added_for_user).with(organization, user, trial.trial_length).returns(mailer).once
    CopilotEnterpriseMailer.expects(:trial_seat_added_for_user).never
    CopilotEnterpriseMailer.expects(:welcome_individual).never
    CopilotForBusinessMailer.expects(:seat_added_for_user).never

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
      end
    end
    refute_match "Deleting any FreeUser records", logs
  end

  test "notifies the user that they have been assigned a Copilot Enterprise trial seat" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
    trial = create(:copilot_business_trial, :organization, trialable: organization, state: :recently_started, copilot_plan: "enterprise")
    organization.add_member(user)
    create(:copilot_seat, organization: organization, assigned_user: user)

    mailer = mock
    mailer.stubs(:deliver_later)

    CopilotEnterpriseMailer.expects(:trial_seat_added_for_user).with(organization, user, trial.trial_length).returns(mailer).once
    CopilotForBusinessMailer.expects(:trial_seat_added_for_user).never
    CopilotEnterpriseMailer.expects(:welcome_individual).never
    CopilotForBusinessMailer.expects(:seat_added_for_user).never

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
      end
    end
    refute_match "Deleting any FreeUser records", logs
  end

  test "notifies the user that they have been assigned a paid seat when an organization has an inactive trial" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    create(:copilot_business_trial, trialable: organization, state: :expired)
    organization.add_member(user)
    create(:copilot_seat, organization: organization, assigned_user: user)

    mailer = mock
    mailer.stubs(:deliver_later)

    CopilotForBusinessMailer.expects(:seat_added_for_user).with(organization, user).returns(mailer).once
    CopilotEnterpriseMailer.expects(:welcome_individual).never
    CopilotForBusinessMailer.expects(:trial_seat_added_for_user).never
    CopilotEnterpriseMailer.expects(:trial_seat_added_for_user).never

    logs = capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
      end
    end
    assert_match "Deleting any FreeUser records", logs
  end

  test "deletes the Copilot free user subscription if it exists" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    organization.add_member(user)
    create(:copilot_seat, organization: organization, assigned_user: user)

    create(:copilot_free_user, user: user)

    capture_logs do
      assert_changes -> { Copilot::FreeUser.count }, from: 1, to: 0 do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
        end
      end
    end
  end

  test "refunds the user if they have a CFI subscription and does not send an email" do
    user = create(:user)

    organization = create(:copilot_for_business_enabled_organization)
    organization.add_member(user)
    create(:copilot_seat, organization: organization, assigned_user: user)

    subscription = create(
      :billing_subscription_item,
      :with_copilot_product_uuid,
      plan_subscription: create(:billing_plan_subscription, user: user),
    )

    CopilotForBusinessMailer
      .expects(:seat_added_for_user)
      .never

    ::Billing::Public::SubscriptionItem
      .expects(:cancel_and_refund)
      .with(
        account: user,
        organization: organization,
        product: subscription.product_uuid,
        allow_cancelling_iap: true
      )
      .returns(GitHub::Result.new { true })
      .once

    capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(
          organization.id, user.id
        )
      end
    end
  end

  test "does not delete the Copilot free user subscription if the org is trialing CfB" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    create(:copilot_business_trial, :organization, trialable: organization, state: :recently_started)
    organization.add_member(user)
    create(:copilot_seat, organization: organization, assigned_user: user)

    create(:copilot_free_user, user: user)

    capture_logs do
      assert_no_changes -> { Copilot::FreeUser.count } do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
        end
      end
    end
  end

  test "does not refund the user if they have a CFI subscription and the org is trialing CfB" do
    user = create(:user)

    organization = create(:copilot_for_business_enabled_organization)
    create(:copilot_business_trial, :organization, trialable: organization, state: :recently_started)

    organization.add_member(user)
    create(:copilot_seat, organization: organization, assigned_user: user)

    subscription = create(
      :billing_subscription_item,
      :with_copilot_product_uuid,
      plan_subscription: create(:billing_plan_subscription, user: user),
    )

    CopilotForBusinessMailer
      .expects(:seat_added_for_user)
      .never

    ::Billing::Public::SubscriptionItem
      .expects(:cancel_and_refund)
      .with(
        account: user,
        organization: organization,
        product: subscription.product_uuid,
      )
      .returns(GitHub::Result.new { true })
      .never

    capture_logs do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(
          organization.id, user.id
        )
      end
    end
  end

  test "queues a job to update the status of the MemberFeatureRequest" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    organization.add_member(user)

    create(:copilot_seat, organization: organization, assigned_user: user)

    assert_enqueued_with(job: MemberFeatureRequest::CopilotForBusinessSeatStatusJob, args: [organization_id: organization.id, user_id: user.id]) do
      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::SeatAssignedJob.perform_now(organization.id, user.id)
      end
    end
  end
end if GitHub.copilot_enabled?
