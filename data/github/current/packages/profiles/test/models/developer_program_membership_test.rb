# typed: true
# frozen_string_literal: true

require "test_helper"

class DeveloperProgramMembershipTest < GitHub::TestCase
  include HydroTestHelpers

  setup do
    ActionMailer::Base.deliveries.clear
  end

  context "#new" do
    test "success" do
      user = create(:user)
      member = DeveloperProgramMembership.new \
        user: user,
        actor: user,
        support_email: Sham.email,
        website: "http://example.com"
      assert member.save, member.errors.full_messages.join
      assert member.active
      assert member.display_badge
    end

    test "orgs" do
      user = create(:user)
      member = DeveloperProgramMembership.new \
        user: create(:organization),
        actor: user,
        support_email: Sham.email,
        website: "http://example.com"
      assert member.save, member.errors.full_messages.join
      assert member.active
      assert member.display_badge
    end

    test "requires an actor" do
      user = create(:user)
      member = DeveloperProgramMembership.new \
        user: user,
        support_email: Sham.email,
        website: "http://example.com"
      refute member.save
      assert_equal [
        "can't be blank",
        "must be a user",
        ], member.errors[:actor]
    end

    test "requires email" do
      user = create(:user)
      member = DeveloperProgramMembership.new \
        user: user,
        actor: user,
        website: "http://example.com"
      refute member.save
      assert_equal [
        "can't be blank",
        "is too short (minimum is 3 characters)",
        "does not look like an email address",
        ], member.errors[:support_email]
    end

    test "requires website" do
      user = create(:user)
      member = DeveloperProgramMembership.new \
        user: user,
        actor: user,
        support_email: Sham.email
      refute member.save
      assert_equal ["can't be blank"], member.errors[:website]
    end
  end

  test "#send_welcome_email" do
    user = create(:user)
    membership = create :developer_program_membership, user: user,
      support_email: Sham.email, website: "http://example.com",
      actor: user
    assert_performed_email(mailer: "DeveloperProgramMembershipMailer", action: "welcome", args: [user]) do
      membership.send_welcome_email
    end
  end

  test "#leave_program" do
    user = create(:user)
    member = create :developer_program_membership, user: user
    assert user.developer_program_member?

    member.leave_program

    refute member.active
    refute user.reload.developer_program_member?
  end

  context "instrument metadata recalculation messages", skip_enterprise: true do
    test "instrument message when user leaves program" do
      user = create(:user)
      membership = create(:developer_program_membership, user: user)
      message = {
        actor: Hydro::EntitySerializer.user(user),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        target_user: Hydro::EntitySerializer.user(user),
        target_stream_processor: :DEVELOPER_PROGRAM_MEMBERSHIP,
      }

      membership.leave_program

      assert_hydro_published(message, schema: "github.user_metadata.v1.Recalculation")
      assert_hydro_messages(
        count: 2, # 2 because there is 1 message for creation, and 1 for leaving the program
        schema: "github.user_metadata.v1.Recalculation",
      )
    end

    test "instrument message when a membership is created" do
      user = create(:user)
      message = {
        actor: Hydro::EntitySerializer.user(user),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        target_user: Hydro::EntitySerializer.user(user),
        target_stream_processor: :DEVELOPER_PROGRAM_MEMBERSHIP,
      }

      create(:developer_program_membership, user: user)

      assert_hydro_published(message, schema: "github.user_metadata.v1.Recalculation")
      assert_hydro_messages(count: 1, schema: "github.user_metadata.v1.Recalculation")
    end

    test "instrument message when the membership is destroyed" do
      user = create(:user)
      membership = create(:developer_program_membership, user: user)
      message = {
        actor: Hydro::EntitySerializer.user(user),
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        target_user: Hydro::EntitySerializer.user(user),
        target_stream_processor: :DEVELOPER_PROGRAM_MEMBERSHIP,
      }

      membership.destroy

      assert_hydro_published(message, schema: "github.user_metadata.v1.Recalculation")
      assert_hydro_messages(
        count: 2, # 2 because there is 1 message for creation, and 1 for deletion
        schema: "github.user_metadata.v1.Recalculation",
      )
    end
  end

  context ".email_list" do
    test "query" do
      user = create(:user)
      member = create :developer_program_membership, user: user

      list = DeveloperProgramMembership.email_list
      subscriber = list.shift
      assert_equal user.email, subscriber[:email]
      assert_equal user.safe_profile_name, subscriber[:name]
      assert_nil list.shift
    end

    test "add owner email to list" do
      owner = create :user, login: "owner"
      org = create :organization, admin: owner
      member = create :developer_program_membership, user: org, actor: owner

      another_owner = create :user, login: "another-owner"
      org_two = create :organization, admin: another_owner
      member_two = create :developer_program_membership, user: org_two, actor: another_owner

      list = DeveloperProgramMembership.email_list

      subscriber = list.shift
      assert subscriber
      assert_equal owner.email, subscriber[:email]
      assert_equal owner.safe_profile_name, subscriber[:name]

      subscriber = list.shift
      assert subscriber
      assert_equal another_owner.email, subscriber[:email]
      assert_equal another_owner.safe_profile_name, subscriber[:name]

      assert_nil list.shift
    end
  end
end
