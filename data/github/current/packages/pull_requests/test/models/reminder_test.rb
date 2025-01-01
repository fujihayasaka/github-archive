# typed: true
# frozen_string_literal: true

require "test_helper"

class ReminderTest < GitHub::TestCase
  include StringFromBinaryTestHelper

  def every_day_reminder
    build(:reminder, remindable: @org, days: %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday], user: @org.admin)
  end

  def weekday_reminder
    build(:reminder, remindable: @org, days: %w[Monday Tuesday Wednesday Thursday Friday], user: @org.admin)
  end

  def weekend_reminder
    build(:reminder, remindable: @org, days: %w[Saturday Sunday], user: @org.admin)
  end

  fixtures do
    make_trusted_oauth_apps_owner
    @owner = create(:user)
    @org = create(:organization, :with_slack, admin: @owner)
    @repo1 = create(:repository, owner: @org)
    @repo2 = create(:repository, owner: @org)
    @other_repo = create(:repository)

    @team = create(:team, name: "team 1", organization: @org)
    @team2 = create(:team, name: "team 2", organization: @org)
    @team3 = create(:team, name: "team 3", organization: @org)
    [@team, @team2, @team3].each { |team| @repo1.add_team(team, action: :read) }
  end

  context "#time_zone_name" do
    test "can store any TZInfo name" do
      reminder = create(:reminder, user: @owner)

      ReminderScheduling.timezone_options.each do |timezone|
        reminder.time_zone_name = timezone.tzinfo.name
        assert reminder.valid?, "Expected reminder to be valid but there were errors: #{reminder.errors.inspect}"
      end
    end

    test "must be present" do
      reminder = create(:reminder, user: @owner)
      reminder.time_zone_name = ""

      refute reminder.valid?
      assert_equal ["can't be blank"], reminder.errors[:time_zone_name]
    end

    test "must be a valid timezone name" do
      reminder = create(:reminder, user: @owner)
      reminder.time_zone_name = "boom"

      refute reminder.valid?
      assert_equal ["not supported (\"boom\")"], reminder.errors[:time_zone_name]
    end
  end

  context "#remindable" do
    test "must be present" do
      reminder = build(:reminder, remindable: @org, user: @owner)
      reminder.remindable = nil

      refute reminder.valid?
      assert_equal ["can't be blank"], reminder.errors[:remindable]
    end

    test "supports private repos" do
      reminder = build(:reminder, remindable: @org, user: @owner)
      assert_predicate reminder, :supports_private_repos?
    end

    test "nil remindable doesnt support private repos" do
      reminder = build(:reminder, user: @owner, remindable: @org)
      reminder.remindable = nil

      refute_predicate reminder, :supports_private_repos?
    end

    test "doesn't support private repos on org free plan" do
      free_org = create(:organization, admin: @owner, plan: "free")
      reminder = build(:reminder, user: @owner, remindable: free_org)
      refute_predicate reminder, :supports_private_repos?
    end
  end

  context "#description" do
    context "free org plan" do
      test "is free plan" do
        free_org = create(:organization, admin: @owner, plan: "free")
        reminder = build(:reminder, user: @owner, remindable: free_org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", ignore_draft_prs: true)
        assert_equal "Any non-draft pull request on all public repositories in the #{reminder.remindable.name} organization", reminder.description
      end
    end

    context "ignore_draft_prs" do
      test "ignore_draft_prs is false" do
        reminder = build(:reminder, user: @owner, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", ignore_draft_prs: true)
        assert_equal "Any non-draft pull request on all repositories in the #{reminder.remindable.name} organization", reminder.description
      end

      test "ignore_draft_prs is true" do
        reminder = build(:reminder, user: @owner, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", ignore_draft_prs: false)
        assert_equal "Any pull request on all repositories in the #{reminder.remindable.name} organization", reminder.description
      end
    end

    context "ignore_after_approval_count" do
      test "ignore_draft_prs is true" do
        reminder = build(:reminder, user: @owner, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", ignore_after_approval_count: 2)
        assert_equal "Any non-draft pull request with less than 2 approvals on all repositories in the #{reminder.remindable.name} organization", reminder.description
      end
    end

    context "tracked_repositories" do
      test "with 1 repo" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        reminder = build(:reminder, user: @owner, remindable: org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel")
        reminder.tracked_repository_ids = [repo.id]
        assert_equal "Any non-draft pull request on #{repo.name_with_owner}", reminder.description
      end

      test "with 2 repos" do
        org = create(:organization)
        repo = create(:repository, name: "a", owner: org)
        repo2 = create(:repository, name: "b", owner: org)
        reminder = build(:reminder, user: @owner, remindable: org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel")
        reminder.tracked_repository_ids = [repo.id, repo2.id]
        assert_equal "Any non-draft pull request on #{repo.name_with_owner} and #{repo2.name_with_owner}", reminder.description
      end


      test "with private repos" do
        org = create(:organization)
        repo = create(:repository, name: "a", owner: org)
        private_repo = create(:private_repository, name: "b", owner: org)

        reminder = build(:reminder, user: @owner, remindable: org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel")
        reminder.tracked_repository_ids = [repo.id, private_repo.id]
        assert_equal "Any non-draft pull request on #{repo.name_with_owner} and #{private_repo.name_with_owner}", reminder.description

        org.plan = "free"
        org.save
        reminder.reset_memoized_attributes

        reminder.tracked_repository_ids = [repo.id, private_repo.id]
        assert_equal "Any non-draft pull request on #{repo.name_with_owner}", reminder.description
      end

      test "with 3+ repos" do
        org = create(:organization)
        repo = create(:repository, owner: org)
        repo2 = create(:repository, owner: org)
        repo3 = create(:repository, owner: org)
        reminder = build(:reminder, user: @owner, remindable: org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel")
        reminder.tracked_repository_ids = [repo.id, repo2.id, repo3.id]
        assert_equal "Any non-draft pull request on 3 repositories", reminder.description
      end

      test "filters out tracked_repository_ids that aren't accessible to selected teams" do
        reminder = create(:reminder, remindable: @org, teams: [@team], user: @owner)
        reminder.tracked_repository_ids = [@repo1.id, @repo2.id]
        reminder.save

        assert_equal [@repo1.id], reminder.tracked_repository_ids
      end

      test "only retrieves repositories accessible to the reminder" do
        reminder = create(:reminder, remindable: @org, user: @owner)
        reminder.update!(tracked_repository_ids: [@repo1.id, @repo2.id])

        assert_same_elements [@repo1, @repo2], reminder.reload.tracked_repositories
        reminder.update!(teams: [@team])
        assert_same_elements [@repo1], reminder.reload.tracked_repositories
      end

      test "only retrieves non private repositories when a free org" do
        private_repo = create(:private_repository, owner: @org)

        reminder = create(:reminder, remindable: @org, user: @owner)
        reminder.update!(tracked_repository_ids: [@repo1.id, private_repo.id])

        assert_same_elements [@repo1, private_repo], reminder.reload.tracked_repositories

        @org.plan = "free"
        @org.save
        reminder.reset_memoized_attributes

        assert_same_elements [@repo1], reminder.reload.tracked_repositories
      end
    end

    context "team_memberships" do
      test "with 1 team" do
        reminder = build(:reminder, user: @owner, remindable: @org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", teams: [@team])
        assert_equal "Any non-draft pull request requesting review from #{@team.name}", reminder.description
      end

      test "with 2 teams" do
        reminder = build(:reminder, user: @owner, remindable: @org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", teams: [@team, @team2])
        assert_equal "Any non-draft pull request requesting review from #{@team.name} and #{@team2.name}", reminder.description
      end

      test "with 3 teams" do
        reminder = build(:reminder, user: @owner, remindable: @org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", teams: [@team, @team2, @team3])
        assert_equal "Any non-draft pull request requesting review from the 3 selected teams", reminder.description
      end

      test "with teams but include_team is false" do
        reminder = build(:reminder, user: @owner, remindable: @org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", teams: [@team, @team2])
        assert_equal "Any non-draft pull request on all repositories in the #{@org.name} organization", reminder.description(include_team: false)
      end

      test "with require_review_request set to false" do
        reminder = build(:reminder, user: @owner, remindable: @org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", teams: [@team, @team2], require_review_request: false)
        assert_equal "Any non-draft pull request on all repositories in the #{@org.name} organization", reminder.description(include_team: false)
      end
    end
  end

  context "#instrument_destruction" do
    test "raises an error if @delivery_system is not defined and a repo id is set" do
      GitHub.context.push(actor_id: @owner.id)
      reminder = build(:reminder, user: @owner, remindable: @org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", teams: [@team, @team2], require_review_request: false)
      reminder.set_repository_id_for_reminder_to_delete(@repo1.id)
      error = assert_raises(RuntimeError) { reminder.instrument_destruction }
      assert_match /must be called before `instrument_destruction`/, error.message
    end

    test "does not trigger a webhook when repo id is not set" do
      GitHub.context.push(actor_id: @owner.id)
      reminder = build(:reminder, user: @owner, remindable: @org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", teams: [@team, @team2], require_review_request: false)
      Hook::DeliverySystem.any_instance.expects(:deliver_later).never
    end

    test "delivers the webhook payload if @delivery_system is defined and a repo id is set" do
      GitHub.context.push(actor_id: @owner.id)
      Hook::DeliverySystem.any_instance.expects(:deliver_later)

      reminder = build(:reminder, user: @owner, remindable: @org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", slack_channel: "channel", teams: [@team, @team2], require_review_request: false)
      reminder.set_repository_id_for_reminder_to_delete(@repo1.id)
      reminder.generate_webhook_payload
      reminder.instrument_destruction
    end
  end

  context "#slack_channel" do
    test "validation fails when not a valid Slack channel name" do
      reminder = build(:reminder, user: @owner, slack_channel: "not a valid channel")

      refute_predicate reminder, :valid?
      assert reminder.errors[:slack_channel].present?
    end

    test "validation doesnt fail with underscores and dashes" do
      reminder = build(:reminder, user: @owner, slack_channel: "a-valid_channel")
      assert_predicate reminder, :valid?
    end

    test "validation doesnt fail if slack channel starts with # or includes whitespace, they are stripped" do
      reminder = build(:reminder, user: @owner, remindable: @org, slack_channel: "#channel    ")

      assert_predicate reminder, :valid?
      assert_equal "channel", reminder.slack_channel
    end

    test "validation doesnt fail if a channel id is provided when the add by id or name feature is enabled", skip_if_feature_disabled: :scheduled_reminders_add_by_channel_id_or_name do
      reminder = build(:reminder, user: @owner, remindable: @org, slack_channel: "C67HJ65J")

      assert_predicate reminder, :valid?
      assert_equal "C67HJ65J", reminder.slack_channel
    end

    test "validation fails if an invalid channel id is provided when the add by id or name feature is enabled", skip_if_feature_disabled: :scheduled_reminders_add_by_channel_id_or_name do
      reminder = build(:reminder, user: @owner, remindable: @org, slack_channel: "C_67HJ65J")

      refute_predicate reminder, :valid?
      assert reminder.errors[:slack_channel].present?
    end

  end

  context "ignored_terms" do
    test "limits to max length" do
      reminder = build(:reminder, user: @owner, remindable: @org, slack_channel: "#channel", ignored_terms: "a" * 1025)
      refute_predicate reminder, :valid?
      assert reminder.errors[:ignored_terms].present?
    end
  end

  context "ignored_labels" do
    test "limits to max length" do
      reminder = build(:reminder, user: @owner, remindable: @org, slack_channel: "#channel", ignored_labels: "a" * 1025)
      refute_predicate reminder, :valid?
      assert reminder.errors[:ignored_labels].present?
    end
  end

  context "required_labels" do
    test "limits to max length" do
      reminder = build(:reminder, user: @owner, remindable: @org, slack_channel: "#channel", required_labels: "a" * 1025)
      refute_predicate reminder, :valid?
      assert reminder.errors[:required_labels].present?
    end
  end

  context "min_age" do
    test "requires positive number" do
      reminder = build(:reminder, user: @owner, remindable: @org, slack_channel: "#channel", min_age: -9)
      refute_predicate reminder, :valid?
      assert reminder.errors[:min_age].present?
    end
  end

  context "min_staleness" do
    test "requires positive number" do
      reminder = build(:reminder, user: @owner, remindable: @org, slack_channel: "#channel", min_staleness: -9)
      refute_predicate reminder, :valid?
      assert reminder.errors[:min_staleness].present?
    end
  end

  context "remind author settings" do
    test "reset values if require_review_request is false and include_reviewed_prs is true" do
      reminder = build(:reminder, user: @owner, remindable: @org, slack_channel: "#channel", require_review_request: false, include_reviewed_prs: true)
      assert_predicate reminder, :valid?
      assert_equal false, reminder.include_reviewed_prs
    end

    test "resets needed_reviews if include_reviewed_prs is set to false" do
      reminder = build(:reminder, user: @owner, remindable: @org, slack_channel: "#channel", require_review_request: true, include_reviewed_prs: false, needed_reviews: 1)
      assert_predicate reminder, :valid?
      reminder.save!
      assert_equal 0, reminder.reload.needed_reviews
    end
  end

  context "#weekdays?" do
    test "Monday - Friday selected" do
      assert_predicate weekday_reminder, :weekdays?
    end

    test "Monday - Thursday selected" do
      reminder = build(:reminder, user: @owner, days: %w[Monday Tuesday Wednesday Thursday])

      refute_predicate reminder, :weekdays?
    end

    test "Weekdays except Wednesday selected" do
      reminder = build(:reminder, user: @owner, days: %w[Monday Tuesday Thursday Friday])

      refute_predicate reminder, :weekdays?
    end

    test "Monday - Saturday selected" do
      reminder = build(:reminder, user: @owner, days: %w[Monday Tuesday Wednesday Thursday Friday Saturday])

      refute_predicate reminder, :weekdays?
    end
  end

  context "#weekends?" do
    test "Sat/Sun selected" do
      assert_predicate weekend_reminder, :weekends?
    end

    test "Saturday selected" do
      reminder = build(:reminder, user: @owner, days: ["Saturday"])

      refute_predicate reminder, :weekends?
    end

    test "Mon/Sat/Sun selected" do
      reminder = build(:reminder, user: @owner, days: %w[Monday Saturday Sunday])

      refute_predicate reminder, :weekends?
    end
  end

  context "#every_day?" do
    test "Every day selected" do
      assert_predicate every_day_reminder, :every_day?
    end

    test "Every day but Wednesday selected" do
      reminder = build(:reminder, user: @owner, days: %w[Monday Tuesday Thursday Friday Saturday Sunday])

      refute_predicate reminder, :every_day?
    end

    test "Only Monday selected" do
      reminder = build(:reminder, user: @owner, days: ["Monday"])

      refute_predicate reminder, :every_day?
    end
  end

  context "delivery_times_attributes" do
    test "builds delivery time objects" do
      reminder = build(:reminder, user: @owner)
      assert_equal 1, reminder.delivery_times.size
      assert_equal "Monday", reminder.delivery_times.first.day
      assert_equal "9:00 AM", reminder.delivery_times.first.time

      delivery_times_attributes = [
        { "day" => "Saturday", "time" => "9:00 AM" },
        { "day" => "Friday", "time" => "9:00 AM" },
      ]

      reminder.assign_attributes(delivery_times_attributes: delivery_times_attributes)
      reminder.save!

      actual_attributes = reminder.delivery_times.map { |delivery_time| delivery_time.slice("day", "time") }

      assert_equal delivery_times_attributes, actual_attributes
    end

    test "deletes old delivery times" do
      reminder = create(:reminder, days: ["Monday"], times: ["10:00 AM"], user: @owner)
      previous_delivery_times = reminder.delivery_times.to_a

      delivery_times_attributes = [
        { "day" => "Friday", "time" => "9:00 AM" },
      ]

      reminder.assign_attributes(delivery_times_attributes: delivery_times_attributes)
      reminder.save!

      actual_attributes = reminder.delivery_times.map { |delivery_time| delivery_time.slice("day", "time") }
      assert_equal delivery_times_attributes, actual_attributes

      previous_delivery_times.each do |previous_delivery_time|
        assert_raises(ActiveRecord::RecordNotFound) { previous_delivery_time.reload }
      end
    end

    test "replaces existing delivery times" do
      reminder = create(:reminder, remindable: @org, days: %w[Monday Friday], user: @owner)

      delivery_times_attributes = [{ "day" => "Wednesday", "time" => "12:00 PM" }]
      reminder.assign_attributes(delivery_times_attributes: delivery_times_attributes)
      reminder.save!

      actual_attributes = reminder.delivery_times.map { |delivery_time| delivery_time.slice("day", "time") }
      assert_equal delivery_times_attributes, actual_attributes
    end

    test "deletes previous delivery times" do
      reminder = create(:reminder, remindable: @org, days: %w[Monday Friday], user: @owner)

      previous_delivery_times = reminder.delivery_times.to_a
      reminder.assign_attributes(delivery_times_attributes: [{ "day" => "Wednesday", "time" => "12:00 PM" }])
      reminder.save!

      previous_delivery_times.each do |previous_delivery_time|
        assert_raises(ActiveRecord::RecordNotFound) { previous_delivery_time.reload }
      end
    end

    test "reuses existing delivery times" do
      reminder = create(:reminder, remindable: @org, days: ["Monday"], times: ["12:00 PM"], user: @owner)

      previous_delivery_times = reminder.delivery_times.to_a
      assert_equal 1, previous_delivery_times.size
      reminder.assign_attributes(delivery_times_attributes: [{ "day" => reminder.delivery_times.first.day, "time" => reminder.delivery_times.first.time }])
      reminder.save!

      assert_same_elements(previous_delivery_times, reminder.reload.delivery_times)
    end
  end

  context "delivery_times validations" do
    test "fails at database layer when there are duplicate delivery times" do
      reminder = build(:reminder, user: @owner)
      reminder.delivery_times.build(day: "Monday", time: "9:00 AM")
      reminder.delivery_times.build(day: "Monday", time: "9:00 AM")

      assert_raises ActiveRecord::RecordNotUnique do
        reminder.save!(validate: false)
      end
    end

    test "fails validation when there are duplicate delivery times" do
      reminder = build(:reminder, user: @owner)
      reminder.delivery_times.build(day: "Monday", time: "9:00 AM")
      reminder.delivery_times.build(day: "Monday", time: "9:00 AM")

      refute_predicate reminder, :valid?
      assert_equal ["must be unique"], reminder.errors[:delivery_times]
    end
  end

  context "#delivery_days_text" do
    test "returns human-readable string for delivery days" do
      reminder = build(:reminder, user: @owner, days: ["Monday"], times: ["9:00 AM"])

      assert_equal "Mon", reminder.delivery_days_text
    end

    test "formats two days" do
      reminder = build(:reminder, user: @owner, days: %w[Monday Tuesday], times: ["9:00 AM"])

      assert_equal "Mon and Tue", reminder.delivery_days_text
    end

    test "formats multiple days" do
      reminder = build(:reminder, user: @owner, days: %w[Monday Wednesday Friday], times: ["9:00 AM"])

      assert_equal "Mon, Wed, Fri", reminder.delivery_days_text
    end

    test "uses 'weekdays' when possible" do
      assert_equal "Weekdays", weekday_reminder.delivery_days_text
    end

    test "uses 'weekends' when possible" do
      assert_equal "Weekends", weekend_reminder.delivery_days_text
    end

    test "uses 'every day' when possible" do
      assert_equal "Every day", every_day_reminder.delivery_days_text
    end
  end

  context "#delivery_times_text" do
    test "returns human-readable string for delivery times" do
      reminder = build(:reminder, user: @owner, days: ["Monday"], times: ["9:00 AM"])

      assert_equal reminder.delivery_times_text, "Mon at 9:00 AM #{weekend_reminder.time_zone_abbreviation}"
    end

    test "formats two days" do
      reminder = build(:reminder, user: @owner, days: %w[Monday Tuesday], times: ["9:00 AM"])

      assert_equal reminder.delivery_times_text, "Mon and Tue at 9:00 AM #{weekend_reminder.time_zone_abbreviation}"
    end

    test "formats multiple days" do
      reminder = build(:reminder, user: @owner, days: %w[Monday Wednesday Friday], times: ["9:00 AM"])

      assert_equal reminder.delivery_times_text, "Mon, Wed, Fri at 9:00 AM #{weekend_reminder.time_zone_abbreviation}"
    end

    test "uses 'weekdays' when possible" do
      assert_equal weekday_reminder.delivery_times_text, "Weekdays at 9:00 AM #{weekend_reminder.time_zone_abbreviation}"
    end

    test "uses 'weekends' when possible" do
      assert_equal weekend_reminder.delivery_times_text, "Weekends at 9:00 AM #{weekend_reminder.time_zone_abbreviation}"
    end

    test "uses 'every day' when possible" do
      assert_equal every_day_reminder.delivery_times_text, "Every day at 9:00 AM #{weekend_reminder.time_zone_abbreviation}"
    end

    test "formats multiple times" do
      reminder = build(:reminder, user: @owner, days: ["Monday"], times: ["9:00 AM", "12:00 PM", "3:00 PM"])

      assert_equal reminder.delivery_times_text, "Mon at 9:00 AM, 12:00 PM, 3:00 PM #{weekend_reminder.time_zone_abbreviation}"
    end
  end

  context "#days" do
    test "returns unique days from delivery times" do
      assert_equal %w[Saturday Sunday], weekend_reminder.days
    end

    test "returns an empty array when there are no delivery times" do
      reminder = build(:reminder, user: @owner, days: [])

      assert_equal [], reminder.days
    end
  end

  context "#times" do
    test "returns unique times from delivery times" do
      reminder = build(:reminder, user: @owner, days: %w[Monday Tuesday], times: ["9:00 AM", "12:00 PM"])

      assert_equal ["9:00 AM", "12:00 PM"], reminder.times
    end

    test "returns an empty array when there are no delivery times" do
      reminder = build(:reminder, user: @owner, times: [])

      assert_equal [], reminder.times
    end
  end

  context "#tracked_repositories" do
    test "allow setting and getting tracked repository IDs" do
      reminder = build(:reminder, user: @owner, remindable: @org)
      reminder.tracked_repository_ids = [@repo1.id]
      assert_equal [@repo1.id], reminder.tracked_repository_ids
    end

    test "returns tracked repositories" do
      reminder = build(:reminder, user: @owner, remindable: @org)
      reminder.tracked_repository_ids = [@repo1.id]
      assert_equal [@repo1], reminder.tracked_repositories
    end

    test "only stores repositories that belong to organization" do
      reminder = build(:reminder, user: @owner, remindable: @org)
      reminder.tracked_repository_ids = [@other_repo.id]
      reminder.save

      assert_equal [], reminder.tracked_repositories
      assert_equal [], reminder.tracked_repository_ids
    end

    test "tracked repositories are filtered by team when assigned before team" do
      reminder = create(:reminder, user: @owner, remindable: @org)

      # The order is meaningful in this test -- we want to ensure the code does
      # the right thing, even if the team is assigned after the repository IDs.
      reminder.tracked_repository_ids = [@repo1.id, @repo2.id]
      reminder.teams = [@team]

      reminder.save!

      assert_equal [@repo1.id], reminder.tracked_repository_ids
    end
  end

  context "#include_approved?" do
    test "returns false when ignore_after_approval_count is greater than zero" do
      reminder1 = Reminder.new(ignore_after_approval_count: 1)
      reminder2 = Reminder.new(ignore_after_approval_count: 3)
      reminder3 = Reminder.new(ignore_after_approval_count: 2)

      refute_predicate reminder1, :include_approved?
      refute_predicate reminder2, :include_approved?
      refute_predicate reminder3, :include_approved?
    end

    test "returns true when ignore_after_approval_count is zero" do
      reminder = Reminder.new(ignore_after_approval_count: 0)

      assert_predicate reminder, :include_approved?
    end

    test "returns true when ignore_after_approval_count is less than zero" do
      reminder = Reminder.new(ignore_after_approval_count: -1)

      assert_predicate reminder, :include_approved?
    end

    test "returns true when ignore_after_approval_count is nil" do
      reminder = Reminder.new(ignore_after_approval_count: nil)

      assert_predicate reminder, :include_approved?
    end
  end

  context "#too_many_approvals?" do
    test "returns true when there is one approval and we ignore after one approval" do
      reminder = Reminder.new(ignore_after_approval_count: 1)

      assert reminder.too_many_approvals?(1)
    end

    test "returns true when there is two approval and we ignore after one approval" do
      reminder = Reminder.new(ignore_after_approval_count: 1)

      assert reminder.too_many_approvals?(2)
    end

    test "returns false when there is one approval but we don't ignore after approval" do
      reminder = Reminder.new(ignore_after_approval_count: 0) # Zero means we don't ignore after approval

      refute reminder.too_many_approvals?(1)
      refute reminder.too_many_approvals?(2)
      refute reminder.too_many_approvals?(3)
    end
  end

  context "teams association" do
    test "teams from the same organization can be added" do
      reminder = create(:reminder, remindable: @org, user: @owner)

      reminder.update!(teams: @team)

      assert_same_elements Reminder.find(reminder.id).teams, [@team]
    end

    test "invalid if max teams are associated" do
      teams = []
      (Reminder::MAX_ASSOCIATED_TEAMS + 1).times { teams << create(:team, organization: @org) }
      teams.each { |team| @repo1.add_team(team, action: :read) }

      reminder = create(:reminder, remindable: @org, user: @owner)
      reminder.teams = teams

      refute_predicate reminder, :valid?
      assert_equal reminder.errors[:base], ["Cannot have more than #{Reminder::MAX_ASSOCIATED_TEAMS} teams associated to a single reminder"]
    end

    test "valid if max teams are associated" do
      teams = []
      Reminder::MAX_ASSOCIATED_TEAMS.times { teams << create(:team, organization: @org) }
      teams.each { |team| @repo1.add_team(team, action: :read) }

      reminder = create(:reminder, remindable: @org, user: @owner)
      reminder.teams = teams
      assert_predicate reminder, :valid?
    end

    test "teams are deduplicated" do
      reminder = create(:reminder, remindable: @org, user: @owner)

      reminder.update!(teams: [@team, @team])

      assert_same_elements Reminder.find(reminder.id).teams, [@team]
    end

    test "teams are deduplicated on the second round too" do
      reminder = create(:reminder, remindable: @org, user: @owner)

      reminder.update!(teams: [@team])
      reminder.update!(teams: [@team, @team2])

      assert_same_elements Reminder.find(reminder.id).teams, [@team, @team2]
    end

    test "adding a team from another organization fails" do
      reminder = create(:reminder, remindable: @org, user: @owner)
      org2 = create(:organization)
      make_integration_installation(integration: Apps::Privileged.integration(:slack), target: org2)
      team = create(:team, organization: org2)

      reminder.teams = [team]

      refute_predicate reminder, :valid?
      assert_equal reminder.errors[:teams], ["could not all be found"]
    end

    test "adding a team from another organization removes the team association" do
      reminder = create(:reminder, remindable: @org, user: @owner)
      org2 = create(:organization)
      make_integration_installation(integration: Apps::Privileged.integration(:slack), target: org2)
      team = create(:team, organization: org2)

      reminder.teams = [team]
      refute_predicate reminder, :valid?
      assert_equal [], reminder.teams

      reminder.save
      assert_equal [], reminder.teams
    end

    test "reloading object clears teams cache" do
      reminder = create(:reminder, remindable: @org, teams: [@team], user: @owner)

      reminder.teams                                # 1. Cache value
      reminder.team_memberships.build(team: @team2) # 2. Modify association
      reminder.save!
      reminder.reload                               # 3. Reload object

      assert_same_elements reminder.teams, [@team, @team2]
    end

    test "teams can be added by ID" do
      reminder = build(:reminder, remindable: @org, user: @org.admin)
      reminder.update!(team_ids: [@team.id])

      assert_same_elements reminder.teams, [@team]
    end

    test "teams can be added by string ID" do
      reminder = build(:reminder, remindable: @org, user: @org.admin)
      reminder.update!(team_ids: [@team.id.to_s])

      assert_same_elements reminder.teams, [@team]
    end

    test "teams IDs can be retrieved" do
      reminder = create(:reminder, remindable: @org, teams: [@team], user: @owner)

      reminder.update!(team_ids: [@team.id])

      assert_same_elements reminder.team_ids, [@team.id]
    end

    test "null and blank strings are ignored" do
      reminder = create(:reminder, remindable: @org, team_ids: [nil, "", @team.id], user: @owner)

      assert_same_elements reminder.teams, [@team]
    end
  end

  context "#update_next_delivery_times" do
    test "persists next delivery times" do
      a_saturday = Time.parse("2000-01-01Z")
      next_tuesday = Time.parse("2000-01-04Z")
      initial_delivery_times = [Time.parse("2000-01-03T09:00Z"), Time.parse("2000-01-03T12:00Z")]
      next_delivery_times    = [Time.parse("2000-01-10T09:00Z"), Time.parse("2000-01-10T12:00Z")]

      travel_to(a_saturday)

      reminder = create(:reminder, remindable: @org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", user: @owner)

      travel_to(next_tuesday)

      assert_changes -> { reminder.delivery_times.pluck(:next_delivery_at) }, from: initial_delivery_times, to: next_delivery_times do
        reminder.update_next_delivery_times
      end
    end

    test "only updates times that are in the past" do
      a_saturday = Time.parse("2000-01-01Z")
      initial_delivery_times = [Time.parse("2000-01-03T09:00Z"), Time.parse("2000-01-03T12:00Z")]
      next_delivery_times    = [Time.parse("2000-01-10T09:00Z"), Time.parse("2000-01-03T12:00Z")]

      travel_to(a_saturday)

      reminder = create(:reminder, remindable: @org, days: ["Monday"], times: ["9:00 AM", "12:00 PM"], time_zone_name: "UTC", user: @owner)

      travel_to(initial_delivery_times.first + 1)

      reminder.delivery_times.map(&:next_delivery_at)

      assert_changes -> { reminder.delivery_times.pluck(:next_delivery_at) }, from: initial_delivery_times, to: next_delivery_times do
        reminder.update_next_delivery_times
      end
    end
  end

  context "#valid_delivery_at?" do
    test "returns true when given time matches a next_delivery_at value" do
      reminder = weekday_reminder
      reminder.save!

      reminder.delivery_times.each do |delivery_time|
        assert(
          reminder.valid_delivery_at?(delivery_time.next_delivery_at),
          "#{delivery_time.next_delivery_at.inspect} not a valid delivery",
        )
      end
    end

    test "returns false when given time doesn't match next_delivery_at" do
      reminder = weekday_reminder

      refute reminder.valid_delivery_at?(Time.parse("2000-01-01"))
    end
  end

  context "#slack_workspace" do
    test "must belong to same remindable" do
      slack_workspace_from_another_org = create(:slack_workspace)

      reminder = build(:reminder, user: @owner, remindable: @org, slack_workspace: slack_workspace_from_another_org)

      refute_equal slack_workspace_from_another_org.remindable, reminder.remindable
      refute reminder.valid?
      assert_equal ["can't be blank"], reminder.errors[:slack_workspace]
      assert_nil reminder.slack_workspace
    end

    test "scoped to same organization" do
      slack_workspace_from_another_org = create(:reminder_slack_workspace, remindable: create(:organization))
      reminder = create(:reminder, remindable: @org, user: @owner)

      # Store invalid data to database
      reminder.update_column(:reminder_slack_workspace_id, slack_workspace_from_another_org.id)
      reminder.reload

      assert_nil reminder.slack_workspace
      refute reminder.valid?
      assert_equal ["can't be blank"], reminder.errors[:slack_workspace]
    end

    test "supports emoji for name" do
      reminder_slack_workspace = create(:reminder_slack_workspace, name: "we ❤️ emojis")

      assert_multibyte_tracked_changes(reminder_slack_workspace, :name)
    end
  end

  context "#with_repo_nwo" do
    test "returns reminders for both selected ids and reminders set for all repos" do
      repo = create(:repository)

      reminder_for_repo = create(:reminder, remindable: @org, repositories: [repo], user: @owner)
      reminder_all_repos = create(:reminder, remindable: @org, repositories: [], user: @owner)

      scope = Reminder.default_scoped.with_repo_nwo(repo.nwo).map(&:id)

      assert_includes scope, reminder_for_repo.id
      assert_includes scope, reminder_all_repos.id
    end
  end
end

class ReminderValidateAndPostMessageToSlackTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include SlackApiTestHelper

  fixtures do
    @owner = create(:user)
    @org = create(:organization, :with_slack, admin: @owner)
    disable_feature_flag(:reminder_slack_add_channel_async)
  end

  context "channel validation succeeds" do
    test "on successful request to slack" do
      stub_request_to_slack_int_api

      reminder = create(:reminder, remindable: @org, user: @owner)
      reminder.slack_channel_id = nil
      assert reminder.slack_workspace.validate_and_post_message(@owner, "https://example.com", reminder), "should return true when request is successful"
      assert reminder.slack_channel_id
    end

    test "on async creation" do
      enable_feature_flag(:reminder_slack_add_channel_async, @org)
      stub_request_to_slack_int_api

      reminder = create(:reminder, remindable: @org, user: @owner)
      reminder.slack_channel_id = nil
      assert_enqueued_jobs 1, only: Reminders::AddReminderForSlackChannelJob, queue: :reminders do
        assert reminder.slack_workspace.validate_and_post_message(@owner, "https://example.com", reminder), "should return true when request is pending"
      end
      refute reminder.slack_channel_id
    end
  end

  context "channel validation failure" do
    test "on invalid reminder" do
      reminder = build(:reminder, remindable: @org)
      reminder.slack_workspace = nil
      refute_predicate reminder, :valid?
    end

    test "on failed API response", skip_if_feature_disabled: :scheduled_reminders_add_by_channel_id_or_name do
      stub_request_to_slack_int_api(status: 422, response: { "ok" => false, "error" => "you_cant_control_me" })

      reminder = create(:reminder, remindable: @org, user: @owner)
      expected_log = {
        "SeverityText" => "ERROR",
        "code.function" => "validate_and_post_message_to_slack",
        "exception.message" => "you_cant_control_me",
        "gh.actor.id" => @owner.id,
        "gh.scheduled_reminders.action" => "updated"
      }
      assert_logged(**expected_log) do
        refute reminder.slack_workspace.validate_and_post_message(@owner, "https://example.com", reminder), "should return false when request is not successful"
        assert_equal "We encountered issues setting up the reminder on your Slack Channel\. Please try providing the channel id and ensure @github has been invited to the channel\. If this persists, please reach out to our support team\.", reminder.errors[:slack_channel].join
      end
    end

    test "on failed API response", skip_if_feature_enabled: :scheduled_reminders_add_by_channel_id_or_name do
      stub_request_to_slack_int_api(status: 422, response: { "ok" => false, "error" => "you_cant_control_me" })

      reminder = create(:reminder, remindable: @org, user: @owner)
      expected_log = {
        "SeverityText" => "ERROR",
        "code.function" => "validate_and_post_message_to_slack",
        "exception.message" => "you_cant_control_me",
        "gh.actor.id" => @owner.id,
        "gh.scheduled_reminders.action" => "updated"
      }
      assert_logged(**expected_log) do
        refute reminder.slack_workspace.validate_and_post_message(@owner, "https://example.com", reminder), "should return false when request is not successful"
        assert_equal "We encountered issues setting up the reminder on your Slack Channel\. Try again in a few moments\. If this persists, please reach out to our support team\.", reminder.errors[:slack_channel].join
      end
    end

    test "on successful API response with an error on body", skip_if_feature_enabled: :scheduled_reminders_add_by_channel_id_or_name do
      stub_request_to_slack_int_api(status: 200, response: { "ok" => false, "error" => "you_cant_control_me" })

      reminder = create(:reminder, remindable: @org, user: @owner)
      expected_log = {
        "SeverityText" => "ERROR",
        "code.function" => "validate_and_post_message_to_slack",
        "exception.message" => "you_cant_control_me",
        "gh.actor.id" => @owner.id,
        "gh.scheduled_reminders.action" => "updated"
      }
      assert_logged(**expected_log) do
        refute reminder.slack_workspace.validate_and_post_message(@owner, "https://example.com", reminder), "should return false when request is not successful"
        assert_equal "We encountered issues setting up the reminder on your Slack Channel\. Try again in a few moments\. If this persists, please reach out to our support team\.", reminder.errors[:slack_channel].join
      end
    end
  end

  context "errors" do
    test "channel_not_found" do
      stub_request_to_slack_int_api(status: 422, response: { "ok" => false, "error" => "channel_not_found" })

      reminder = create(:reminder, remindable: @org, user: @owner)
      refute reminder.slack_workspace.validate_and_post_message(@owner, "https://example.com", reminder), "should return false when request is not successful"
      assert_equal "The channel (#{reminder.slack_channel}) was not found. Check that it exists and that @github has been invited to it",
        reminder.errors[:slack_channel].join
    end

    test "channel_not_found when API response is 200" do
      stub_request_to_slack_int_api(status: 200, response: { "ok" => false, "error" => "channel_not_found" })

      reminder = create(:reminder, remindable: @org, user: @owner)
      refute reminder.slack_workspace.validate_and_post_message(@owner, "https://example.com", reminder), "should return false when request is not successful"
      assert_equal "The channel (#{reminder.slack_channel}) was not found. Check that it exists and that @github has been invited to it",
        reminder.errors[:slack_channel].join
    end

    test "no_permission" do
      stub_request_to_slack_int_api(status: 422, response: { "ok" => false, "error" => "no_permission" })

      reminder = create(:reminder, remindable: @org, user: @owner)
      refute reminder.slack_workspace.validate_and_post_message(@owner, "https://example.com", reminder), "should return false when request is not successful"
      assert_equal "We don't seem to have access to this channel. Can you invite the GitHub bot to this Slack channel and try again\?",
        reminder.errors[:slack_channel].join
    end

    test "server error", skip_if_feature_enabled: :scheduled_reminders_add_by_channel_id_or_name do
      stub_request_to_slack_int_api(status: 500, response: "Server Error", headers: {})

      reminder = create(:reminder, remindable: @org, user: @owner)
      refute reminder.slack_workspace.validate_and_post_message(@owner, "https://example.com", reminder), "should return false when request is not successful"
      assert_equal "We encountered issues setting up the reminder on your Slack Channel\. Try again in a few moments\. If this persists, please reach out to our support team\.", reminder.errors[:slack_channel].join
    end

    test "server error", skip_if_feature_disabled: :scheduled_reminders_add_by_channel_id_or_name do
      stub_request_to_slack_int_api(status: 500, response: "Server Error", headers: {})

      reminder = create(:reminder, remindable: @org, user: @owner)
      refute reminder.slack_workspace.validate_and_post_message(@owner, "https://example.com", reminder), "should return false when request is not successful"
      assert_equal "We encountered issues setting up the reminder on your Slack Channel\. Please try providing the channel id and ensure @github has been invited to the channel\. If this persists, please reach out to our support team\.", reminder.errors[:slack_channel].join
    end

    test "adds any possible slack error", skip_if_feature_enabled: :scheduled_reminders_add_by_channel_id_or_name do
      generic_error_msg = "We encountered issues setting up the reminder on your Slack Channel\. Try again in a few moments\. If this persists, please reach out to our support team\."

      ReminderSlackChannel::SLACK_ERRORS.each do |err, msg|
        stub_request_to_slack_int_api(status: 422, response: { "ok" => false, "error" => err })

        reminder = create(:reminder, remindable: @org, user: @owner)
        refute reminder.slack_workspace.validate_and_post_message(@owner, "https://example.com", reminder), "should return false when request is not successful"
        assert_equal (msg || generic_error_msg) % reminder.slack_channel, reminder.errors[:slack_channel].join
      end
    end
  end
end

class ReminderAccessibleRepositoryIdsTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    make_trusted_oauth_apps_owner
    @app = create(:slack_integration)
    @repo = create(:repository, owner: @org)
    @slack_workspace = create(:reminder_slack_workspace, remindable: @org, slack_id: "1200")

    @team = create(:team, organization: @org)
    @team_accessible_repo = create(:repository, owner: @org)
    @team_accessible_repo.add_team(@team, action: :write)

    @private_repo = create(:private_repository, owner: @org)

    @a_saturday_time = Time.parse("2000-01-01Z").freeze
  end

  def install_on(repositories:)
    make_integration_installation(
      target: @org,
      integration: @app,
      repositories: repositories,
      permissions: { "metadata" => :read, "contents" => :read },
    )
  end

  def create_reminder_on(repositories: [], teams:, validate: true)
    travel_to(@a_saturday_time) do
      reminder = build(:reminder,
        slack_channel: "my-channel",
        repositories: repositories,
        remindable: @org,
        user: @org.admin,
        slack_workspace: @slack_workspace,
        days: ["Monday"],
        times: ["9:00 AM"],
        time_zone_name: "UTC",
        validate_repository_access: false,
        automate_repository_access: false,
      )
      reminder.teams = teams if teams
      if validate
        reminder.save!
      else
        reminder.save(validate: false)
      end
      reminder
    end
  end

  context "integration_installation_for" do
    test "returns nil when not installed in org" do
      reminder = create_reminder_on(repositories: [], teams: [@team], validate: false)
      assert_nil reminder.integration_installation
    end

    test "returns installation when one exists" do
      installation = install_on(repositories: [])
      reminder = create_reminder_on(repositories: [], teams: [@team])
      assert_equal installation, reminder.integration_installation
    end

    test "returns nil when there is no integration" do
      installation = install_on(repositories: [])
      @app.destroy
      reminder = create_reminder_on(repositories: [], teams: [@team], validate: false)
      assert_nil reminder.integration_installation
    end
  end

  context "accessible_repository_ids_for" do
    context "no installation" do
      test "returns empty array when there is not an installation" do
        reminder = create_reminder_on(repositories: [], teams: [@team], validate: false)
        repo_ids = reminder.accessible_repository_ids
        assert_equal [], repo_ids
      end
    end

    context "integration has access to all repos" do
      context "reminder has access to all repos" do
        context "teams are selected" do
          test "lists only repos the team has access to" do
            installation = install_on(repositories: [])
            reminder = create_reminder_on(repositories: [], teams: [@team])
            repo_ids = reminder.accessible_repository_ids
            assert_equal [@team_accessible_repo.id], repo_ids
          end
        end

        context "teams are not selected" do
          test "returns nil, indicating that we do not need to filter" do
            installation = install_on(repositories: [])
            reminder = create_reminder_on(repositories: [], teams: nil)
            repo_ids = reminder.accessible_repository_ids
            assert_nil repo_ids
          end
        end
      end

      context "reminder does not have access to all repos" do
        context "teams are selected" do
          test "filters out repos the team does not have access to" do
            installation = install_on(repositories: [])
            reminder = create_reminder_on(repositories: [@team_accessible_repo, @repo], teams: [@team])
            repo_ids = reminder.accessible_repository_ids
            assert_equal [@team_accessible_repo.id], repo_ids
          end

          test "doesnt filter out private repos for paid orgs" do
            installation = install_on(repositories: [])
            reminder = create_reminder_on(repositories: [@team_accessible_repo, @private_repo], teams: [])
            repo_ids = reminder.accessible_repository_ids
            assert_same_elements [@team_accessible_repo.id, @private_repo.id], repo_ids
          end

          test "filters out private repos when a free org" do
            installation = install_on(repositories: [])
            reminder = create_reminder_on(repositories: [@team_accessible_repo, @private_repo], teams: [])

            @org.plan = "free"
            @org.save

            repo_ids = reminder.accessible_repository_ids
            assert_same_elements [@team_accessible_repo.id, @private_repo.id], repo_ids
          end
        end

        context "teams are not selected" do
          test "lists all repos the reminder has access to" do
            installation = install_on(repositories: [])
            reminder = create_reminder_on(repositories: [@team_accessible_repo], teams: nil)
            repo_ids = reminder.accessible_repository_ids
            assert_equal [@team_accessible_repo.id], repo_ids
          end
        end
      end
    end

    context "integration does not have access to all repos" do
      context "reminder has access to all repos" do
        context "teams are selected" do
          test "filters to repo based on the team accessibility" do
            installation = install_on(repositories: [@team_accessible_repo, @repo])
            reminder = create_reminder_on(repositories: [], teams: [@team])
            repo_ids = reminder.accessible_repository_ids
            assert_equal [@team_accessible_repo.id], repo_ids
          end

          test "filters to repo based on the team accessibility and installation access" do
            installation = install_on(repositories: [@repo])
            # @team doesn't have access to @repo, so the intersection of these 2 values will be empty
            reminder = create_reminder_on(repositories: [], teams: [@team], validate: false)
            repo_ids = reminder.accessible_repository_ids
            assert_equal [], repo_ids
          end
        end

        context "teams are not selected" do
          test "filters to all teams on the installation" do
            installation = install_on(repositories: [@team_accessible_repo, @repo])
            reminder = create_reminder_on(repositories: [], teams: nil)
            repo_ids = reminder.accessible_repository_ids
            assert_equal [@team_accessible_repo.id, @repo.id].sort, repo_ids.sort
          end

          test "returns repos the installation has access to if reminder has access to them all" do
            installation = install_on(repositories: [@repo])
            reminder = create_reminder_on(repositories: [], teams: nil)
            repo_ids = reminder.accessible_repository_ids
            assert_equal [@repo.id], repo_ids
          end
        end
      end

      context "reminder does not have access to all repos" do
        context "teams are selected" do
          test "filters to what the reminder and installation has access to, combined with team accessibility" do
            installation = install_on(repositories: [@team_accessible_repo, @repo])
            reminder = create_reminder_on(repositories: [@team_accessible_repo], teams: [@team])
            repo_ids = reminder.accessible_repository_ids
            assert_equal [@team_accessible_repo.id], repo_ids
          end

          test "returns empty array if reminder and installation have totally different repos" do
            # Installation has access to team_accessible_repo, but reminder doesnt
            installation = install_on(repositories: [@team_accessible_repo])
            reminder = create_reminder_on(teams: [@team], validate: false)

            # Link reminder to repository manually to create an odd state.
            # (Normally, a before_save filters out bad repository IDs.)
            reminder.repository_links.create!(repository_id: @repo.id)

            assert_equal [], reminder.accessible_repository_ids
          end

          test "returns empty array if reminder and installation have the same repos, but team does not have access" do
            # Installation and reminder has access to repo, but team doesn't
            installation = install_on(repositories: [@repo])
            reminder = create_reminder_on(repositories: [@repo], teams: [@team], validate: false)
            repo_ids = reminder.accessible_repository_ids
            assert_equal [], repo_ids
          end
        end

        context "schedule reminder teams parity feature flag enabled" do
          test "filters only the repos the user has access to" do
            admin = create(:user)
            non_admin = create(:user)

            enable_feature_flag(:scheduled_reminders_teams_parity, non_admin)

            org = create(:organization, :with_slack, :with_msteams, admin: admin)
            org.update_default_repository_permission(:none, actor: org.admins.first)
            org.add_member(non_admin)
            repo = create(:repository, owner: org)
            repo.add_member(non_admin, action: :write)
            other_repo = create(:private_repository, owner: org)

            teams_workspace = create(:reminder_teams_workspace, name: "Work 👨‍🚀", remindable: org)
            reminder = build(:reminder, remindable: org, user: non_admin, slack_workspace: teams_workspace)
            repo_ids = reminder.accessible_repository_ids
            assert_equal [repo.id], repo_ids
          end

          test "accessible repo id's is nil when an admin creates the reminder" do
            admin = create(:user)

            enable_feature_flag(:scheduled_reminders_teams_parity, admin)

            org = create(:organization, :with_slack, :with_msteams, admin: admin)
            repo = create(:repository, owner: org)
            other_repo = create(:repository, owner: org)

            teams_workspace = create(:reminder_teams_workspace, name: "Work 👨‍🚀", remindable: org)
            reminder = build(:reminder, remindable: org, user: admin, slack_workspace: teams_workspace)
            repo_ids = reminder.accessible_repository_ids
            assert_nil repo_ids
          end
        end

        context "teams are not selected" do
          test "filters to what the installation and reminder has access to" do
            # Reminder and installation have differing repos, but end set isn't empty because of an intersection
            installation = install_on(repositories: [@team_accessible_repo, @repo])
            reminder = create_reminder_on(repositories: [@team_accessible_repo], teams: nil)
            repo_ids = reminder.accessible_repository_ids
            assert_equal [@team_accessible_repo.id], repo_ids
          end

          test "returns empty array if reminder and installation have totally different repos" do
            installation = install_on(repositories: [@team_accessible_repo])
            reminder = create_reminder_on(repositories: [@repo], teams: nil, validate: false)
            repo_ids = reminder.accessible_repository_ids
            assert_equal [], repo_ids
          end

          test "returns all repos both have access to" do
            # Access to everything both installation and reminder has access to
            installation = install_on(repositories: [@team_accessible_repo, @repo])
            reminder = create_reminder_on(repositories: [@team_accessible_repo, @repo], teams: nil)
            repo_ids = reminder.accessible_repository_ids
            assert_equal [@team_accessible_repo.id, @repo.id].sort, repo_ids.sort
          end
        end
      end
    end
  end

  context "all_repos_are_public" do
    test "no errors when not a free org" do
      install_on(repositories: [])
      @org.plan = "silver"
      @org.save

      reminder = build(:reminder, user: @org.admin, remindable: @org)
      reminder.tracked_repository_ids = [@repo.id, @private_repo.id]
      assert_predicate reminder, :valid?
    end

    test "errors when a free org and have private repos selected" do
      install_on(repositories: [])
      @org.plan = "free"
      @org.save

      reminder = build(:reminder, user: @org.admin, remindable: @org)
      reminder.tracked_repository_ids = [@repo.id, @private_repo.id]
      refute_predicate reminder, :valid?
      assert_match(/organization does not allow you to add reminders for private repositories/, reminder.errors[:base].to_sentence)
    end

    test "no errors when a free org and don't have private repos selected" do
      install_on(repositories: [])
      @org.plan = "free"
      @org.save

      reminder = build(:reminder, user: @org.admin, remindable: @org)
      reminder.tracked_repository_ids = [@repo.id]
      assert_predicate reminder, :valid?
    end
  end

  test "#flipper_id" do
    reminder = create(:reminder, remindable: create(:organization, :with_slack))

    assert_equal "Reminder:#{reminder.id}", reminder.flipper_id
  end
end
