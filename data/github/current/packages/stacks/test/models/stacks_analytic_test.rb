# typed: true
# frozen_string_literal: true

require "test_helper"

class StacksAnalyticTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @helper = FakeHelper.new
    @helper.extend StacksHelper

    @pub_user = create(:user, login: "public-user")
    @user = create(:user)

    @released_stack_template_repo = create(:repository, name: "released-stack-template-repo", template: true, owner: @pub_user)
    @released_repository_stack = create(:repository_stack, :with_example_repository, name: "my-released-stack-template", repository: @released_stack_template_repo)
    @repository_stack_release = create(:repository_stack_release, :unpublished, repository_stack: @released_repository_stack)
    create :release, name: "Version One!", tag_name: "v1.0", author: @released_stack_template_repo.owner, repository: @released_stack_template_repo

    @stack_instance_repo = create(:repository, name: "public-stack-instance-repo", owner: @pub_user, template: false)
    @stack_instance = create(:stacks_instance, instance_repo: @stack_instance_repo, stack_template_repo: @released_stack_template_repo, ref: "refs/tags/v1.0", template_repository_id: @released_stack_template_repo.id)

  end

  setup do
    @helper.stubs(:user_feature_enabled?).returns(true)
    GitHub.stubs(:stacks_enabled?).returns(true)
    GitHub.flipper[:stacks_toggle].enable
  end

  context "StacksAnalytic update" do
    test "instance counts are incremented on increment_instance_counts" do
      stack_analytic = StacksAnalytic.create(template_repository_id: @released_stack_template_repo.id, total_instance_count: 20, present_day_instance_count: 1, last_29_days_instance_counts: [])
      stack_analytic.increment_instance_counts
      assert_equal 2, stack_analytic.present_day_instance_count
      assert_equal 21, stack_analytic.total_instance_count
    end

    test "Update last 29 days data and reset present day count" do
      current_date = Time.now.utc.to_date
      stack_analytic = StacksAnalytic.create(template_repository_id: @released_stack_template_repo.id, present_day_instance_count: 2, last_29_days_instance_counts: [
        { "date" => (current_date - 31).to_date, "count" => 4 }
      ])
      stack_analytic.update_last_29_days_data_and_reset_present_day_count
      assert_equal 1, stack_analytic.present_day_instance_count
      assert_equal [{ "date" => current_date.to_s, "count" => 2 }], stack_analytic.last_29_days_instance_counts
    end

    test "Update popularity count is able to execute increment_instance_counts" do
      stack_analytic = StacksAnalytic.create(template_repository_id: @released_stack_template_repo.id, total_instance_count: 20, present_day_instance_count: 1, last_29_days_instance_counts: [])
      stack_analytic.update_popularity_count
      assert_equal 2, stack_analytic.present_day_instance_count
      assert_equal 21, stack_analytic.total_instance_count
    end

    test "Update popularity count is able to execute update_last_29_days_data_and_reset_present_day_count" do
      current_utc_time = Time.now.utc
      stack_analytic = StacksAnalytic.create(template_repository_id: @released_stack_template_repo.id, present_day_instance_count: 2, last_29_days_instance_counts: [
        { "date" => (current_utc_time.to_date - 31).to_date, "count" => 4 }
      ],
      updated_at: current_utc_time.to_date - 1)
      stack_analytic.update_popularity_count
      assert_equal 1, stack_analytic.present_day_instance_count
      assert_equal [{ "date" => (current_utc_time.to_date - 1).to_date.to_s, "count" => 2 }], stack_analytic.last_29_days_instance_counts
    end
  end

  context "StacksAnalytic updated_today returns" do
    test "true if updated_at is today" do
      stack_analytic = StacksAnalytic.create(template_repository_id: @released_stack_template_repo.id, total_instance_count: 20, present_day_instance_count: 1, last_29_days_instance_counts: [])
      assert_equal true, stack_analytic.updated_today?
    end
    test "false if updated_at is not today" do
      stack_analytic = StacksAnalytic.create(template_repository_id: @released_stack_template_repo.id, present_day_instance_count: 2, last_29_days_instance_counts: [], updated_at: Time.now.utc.to_date - 1.0)
      assert_equal false, stack_analytic.updated_today?
    end
  end

  context "Compute Stack Popularity" do
    test "Update popularity count is able to execute if stack_analytic is present" do
      stack_analytic = StacksAnalytic.create(template_repository_id: @released_stack_template_repo.id, total_instance_count: 20, present_day_instance_count: 1, last_29_days_instance_counts: [])
      stack_analytic.update_popularity_count
      assert_equal 2, stack_analytic.present_day_instance_count
      assert_equal 21, stack_analytic.total_instance_count
    end
    test "New stack analytic is created if stack_analytic is not present" do
      assert_equal false, StacksAnalytic.exists?(template_repository_id: @stack_instance.template_repository_id)
      StacksAnalytic.compute_stack_popularity(@stack_instance)
      assert_equal true, StacksAnalytic.exists?(template_repository_id: @stack_instance.template_repository_id)
    end
  end
end
