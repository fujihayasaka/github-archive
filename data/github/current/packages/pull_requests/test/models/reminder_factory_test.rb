# typed: false
# frozen_string_literal: true

require "test_helper"

class ReminderFactoryTest < GitHub::TestCase
  def create_reminder(automate_repository_access: true, validate_repository_access: true)
    org = create(:organization)
    slack_integration = create(:slack_integration)
    team = create(:team, organization: org)
    make_integration_installation(
      integration: slack_integration,
      target: org,
    )
    create(:reminder,
      remindable: org,
      teams: [team],
      automate_repository_access: automate_repository_access,
      validate_repository_access: validate_repository_access,
      user: org.admin,
    )
  end

  test "works without any parameters" do
    reminder = nil
    assert_nothing_raised do
      reminder = create(:reminder)
    end

    refute_nil reminder.integration_installation
  end

  context "automate_repository_access" do
    test "doesnt auto-create repos if automate_repository_access=false" do
      err = assert_raises(ActiveRecord::RecordInvalid) do
        create_reminder(automate_repository_access: false)
      end
      assert_match /Validation failed: No repositories visible/, err.message
    end

    test "auto-creates repos if automate_repository_access=true" do
      assert_difference "Repository.count" do
        assert_difference "Reminder.count" do
          create_reminder(automate_repository_access: true)
        end
      end
    end
  end

  context "validate_repository_access" do
    test "doesnt validate repos access if validate_repository_access=false" do
      assert_difference "Reminder.count" do
        create_reminder(automate_repository_access: false, validate_repository_access: false)
      end
    end
  end


  context "NoIntegrationInstallationError" do
    test "factory errors when Slack integration isn't installed in organization" do
      org = create(:organization)
      err = assert_raises(ReminderFactory::NoIntegrationInstallationError) do
        create(:reminder, remindable: org)
      end

      assert_match /The Slack integration isn't installed in the reminder's organization/, err.message
    end
  end

  context "NoTrackedRepoIdsError" do
    test "errors when repos given but they arent accessible" do
      org = create(:organization)
      slack_integration = create(:slack_integration)
      make_integration_installation(
        integration: slack_integration,
        target: org,
      )
      repo = create(:repository, owner: org)
      team = create(:team, organization: org)

      err = assert_raises(ReminderFactory::NoTrackedRepoIdsError) do
        create(:reminder,
          remindable: org,
          repositories: [repo],
          teams: [team],
          user: org.admin,
        )
      end

      assert_match /This reminder would have access to no repositories/, err.message
      assert_match /please add `automate_repository_access: false`/, err.message
    end

    test "does not error if repos are accessible" do
      org = create(:organization)
      slack_integration = create(:slack_integration)
      make_integration_installation(
        integration: slack_integration,
        target: org,
      )
      repo = create(:repository, owner: org)
      team = create(:team, organization: org)
      repo.add_team(team, action: :read)

      assert_difference "Reminder.count" do
        create(:reminder,
          remindable: org,
          repositories: [repo],
          teams: [team],
          user: org.admin,
        )
      end
    end
  end

  context "NotInstalledOnAllReposError" do
    test "errors when repos arent accessible and slack integration is not installed on everything" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      slack_integration = create(:slack_integration)
      make_integration_installation(
        integration: slack_integration,
        target: org,
        repositories: [repo],
      )

      team = create(:team, organization: org)
      err = assert_raises(ReminderFactory::NotInstalledOnAllReposError) do
        create(:reminder,
          remindable: org,
          teams: [team],
          user: org.admin,
        )
      end

      assert_match /We tried to create an accessible repository for you/, err.message
      assert_match /slack integration is not installed on all repositories/, err.message
      assert_match /automate_repository_access: false/, err.message
    end

    test "does not error if repos are accessible" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      slack_integration = create(:slack_integration)
      make_integration_installation(
        integration: slack_integration,
        target: org,
        repositories: [repo],
      )

      assert_difference "Reminder.count" do
        create(:reminder,
          remindable: org,
          repositories: [repo],
          user: org.admin,
        )
      end
    end
  end
end
