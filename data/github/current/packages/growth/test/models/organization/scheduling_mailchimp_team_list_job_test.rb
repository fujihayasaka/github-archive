# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationSchedulingMailchimpTeamListJobTest < GitHub::TestCase
  fixtures do
    @member       = create(:user)
    @admin        = create(:user)
    @org          = create(:organization, admin: @admin, plan: GitHub::Plan.business)
    @second_admin = create(:user)
  end

  if GitHub.mailchimp_enabled?
    test "when creating an org queues job to enroll user in team admin onboarding email campaign" do
      assert_enqueued_with(job: MailchimpTeamListJob) do
        create(:organization, admin: @admin, plan: GitHub::Plan.business_plus)
      end
    end

    test "when adding an admin queues job to enroll user in team admin onboarding email campaign" do
      MailchimpTeamListJob.expects(:perform_later).with(user: @second_admin, org: @org)
      @org.add_member(@second_admin, action: :admin)
    end

    test "when adding a member queues job to enroll user in team admin onboarding email campaign" do
      MailchimpTeamListJob.expects(:perform_later).with(user: @member, org: @org)
      @org.add_member(@member, action: :read)
    end

    test "when removing an admin queues job to unenroll user in team admin onboarding email campaign" do
      @org.add_member(@second_admin, action: :admin)
      @org.reload
      MailchimpTeamListJob.expects(:perform_later).with(user: @second_admin, org: @org)
      @org.remove_member!(@second_admin)
    end

    test "when removing a member does not queue job for team admin onboarding email campaign" do
      @org.add_member(@member, action: :read)

      MailchimpTeamListJob.expects(:perform_later).with(user: @member, org: @org)
      @org.remove_member!(@member)
    end

    test "when updating an admin to a member queues job to unenroll user in team admin onboarding email campaign" do
      @org.add_member(@second_admin, action: :admin)
      @org.reload
      MailchimpTeamListJob.expects(:perform_later).with(user: @second_admin, org: @org)
      @org.update_member(@second_admin, action: :read)
    end

    test "when updating a member to an admin queues job to enroll user in team admin onboarding email campaign" do
      @org.add_member(@member, action: :read)
      MailchimpTeamListJob.expects(:perform_later).with(user: @member, org: @org)
      @org.update_member(@member, action: :admin)
    end

    test "when updating a member to something else does not queue job for team admin onboarding email campaign" do
      @org.add_member(@member, action: :read)
      MailchimpTeamListJob.expects(:perform_later).never
      @org.update_member(@member, action: :write)
    end
  else
    test "#add_member should not enqueue job" do
      assert_no_enqueued_jobs only: MailchimpTeamListJob do
        org = create(:organization, admin: @admin)
        org.add_member(@member)
      end
    end

    test "#update_member should not enqueue job" do
      org = create(:organization, admin: @admin)
      org.add_member(@member)
      assert_no_enqueued_jobs only: MailchimpTeamListJob do
        org.update_member(@member, action: :admin)
      end
    end

    test "#remove_member! should not enqueue job" do
      org = create(:organization, admin: @admin)
      org.add_member(@member)
      assert_no_enqueued_jobs only: MailchimpTeamListJob do
        org.remove_member!(@member)
      end
    end
  end
end
