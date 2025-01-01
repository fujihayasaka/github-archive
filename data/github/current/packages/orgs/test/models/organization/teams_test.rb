# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationTeamsTest < GitHub::TestCase
  context "can_create_team?" do
    test "can be created by an owner" do
      org  = create(:organization)
      user = create(:user)
      org.add_admin(user)

      assert org.can_create_team?(user)
    end

    test "can be created by a member" do
      org  = create(:organization)
      user = create(:user)
      org.add_member(user)

      assert org.can_create_team?(user)
    end

    test "cannot be created by a member if setting disabled" do
      org   = create(:organization)
      admin = create(:user)
      user  = create(:user)
      org.add_admin(admin)
      org.add_member(user)
      org.block_members_from_creating_teams(actor: admin)

      refute org.can_create_team?(user)
    end

    test "can't be created by a stranger" do
      org = create(:organization)
      user = create(:user)

      refute org.can_create_team?(user)
    end
  end

  context "update_team_privacy" do
    test "can make all of the teams on the org secret" do
      org = create(:organization)
      create(:team, organization: org, privacy: :closed)

      refute org.teams.all? { |t| t.secret? }

      perform_enqueued_jobs(only: [UpdateOrganizationTeamPrivacyJob]) { org.update_team_privacy(:secret) }
      org.reload

      assert org.teams.all? { |t| t.secret? }
    end

    test "can make all of the teams on the org closed" do
      org = create(:organization)
      create(:team, organization: org, privacy: :secret)

      refute org.teams.all? { |t| t.closed? }

      perform_enqueued_jobs(only: [UpdateOrganizationTeamPrivacyJob]) { org.update_team_privacy(:closed) }
      org.reload

      assert org.teams.all? { |t| t.closed? }
    end

    test "errors if called with an invalid privacy" do
      org = create(:organization)

      assert_raises ArgumentError do
        org.update_team_privacy(:invalid)
      end
    end

    test "errors if called while the privacy is already being updated" do
      org = create(:organization)
      org.stubs(:updating_team_privacy?).returns(true)

      assert_raises Organization::AlreadyUpdatingTeamPrivacy do
        org.update_team_privacy(:closed)
      end
    end
  end

  context "updating_team_privacy?" do
    test "is false before the update has started" do
      org = create(:organization)
      refute org.updating_team_privacy?
    end

    test "is true when the update started less than 10 minutes ago" do
      Timecop.freeze(Time.new(2015, 3, 18)) do
        org = create(:organization)
        org.update(updated_team_privacy_at: 9.minutes.ago)
        assert org.updating_team_privacy?
      end
    end

    test "is false when the update started more than 10 minutes ago" do
      Timecop.freeze(Time.new(2015, 3, 18)) do
        org = create(:organization)
        org.update(updated_team_privacy_at: 11.minutes.ago)
        refute org.updating_team_privacy?
      end
    end

    test "is false after updating the action" do
      org = create(:organization)

      org.update_team_privacy(:closed)

      assert org.updating_team_privacy?
    end
  end
end
