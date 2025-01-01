# typed: true
# frozen_string_literal: true

require "test_helper"

class CreateUnlabeledEventJobTest < GitHub::TestCase
  fixtures do
    @user = create :user
    @repo = create :repository, owner: @user
    @issue = create :issue, repository: @repo
    @label = create :label, name: "foo", repository: @repo
    @issue.labels << @label
    @issue.save!
  end

  setup do
    @label.delete
  end

  test "unlabeled event is created with necessary denormalized data" do
    Timecop.freeze do
      unlabeled_at = Time.now.utc

      # travelling to verify the saved time is really the same as the time we set
      Timecop.travel(1.hour.from_now) do
        CreateUnlabeledEventJob.perform_now(@user.id, [@issue.id], unlabeled_at, @label.id, @label.name, @label.color)
      end

      assert_equal 1, @issue.events.count
      event = @issue.events.first

      assert_equal "unlabeled", event.event
      assert_equal @user, event.actor
      assert_nil event.label
      assert_equal @label.name, event.label_name
      assert_equal @label.color, event.label_color
      assert_equal @label.id, event.label_id
      # using unix timestamp for comparison to deal with micro precision loss going from in mem to db and back
      assert_equal unlabeled_at.to_i, event.created_at.to_i
    end
  end

  test "works through multiple issue_ids" do
    Timecop.freeze do
      issue2 = create :issue, repository: @repo
      label = create :label, name: "foo", repository: @repo
      issue2.labels << label
      issue2.save!

      unlabeled_at = Time.now.utc

      perform_enqueued_jobs only: [CreateUnlabeledEventJob] do
        CreateUnlabeledEventJob.perform_later(@user.id, [@issue.id, issue2.id], unlabeled_at, @label.id, @label.name, @label.color)
      end

      [@issue, issue2].each do |target_issue|
        assert_equal 1, target_issue.events.count
        event = target_issue.events.first

        assert_equal "unlabeled", event.event
        assert_equal @user, event.actor
        assert_nil event.label
        assert_equal @label.name, event.label_name
        assert_equal @label.color, event.label_color
        assert_equal @label.id, event.label_id
        assert_equal unlabeled_at.to_i, event.created_at.to_i
      end
    end
  end

  test "handles deleted issues gracefully" do
    Timecop.freeze do
      issue2 = create :issue, repository: @repo
      label = create :label, name: "foo", repository: @repo
      issue2.labels << label
      issue2.save!

      @issue.delete

      unlabeled_at = Time.now.utc

      perform_enqueued_jobs only: [CreateUnlabeledEventJob] do
        CreateUnlabeledEventJob.perform_later(@user.id, [@issue.id, issue2.id], unlabeled_at, @label.id, @label.name, @label.color)
      end

      assert_equal 1, issue2.events.count
      event = issue2.events.first

      assert_equal "unlabeled", event.event
      assert_equal @user, event.actor
      assert_nil event.label
      assert_equal @label.name, event.label_name
      assert_equal @label.color, event.label_color
      assert_equal @label.id, event.label_id
      assert_equal unlabeled_at.to_i, event.created_at.to_i
    end
  end

  test "does not create duplicate unlabeled events" do
    unlabeled_at = Time.now.utc

    assert_equal 0, @issue.events.count

    CreateUnlabeledEventJob.perform_now(@user.id, [@issue.id], unlabeled_at, @label.id, @label.name, @label.color)
    assert_equal 1, @issue.events.count

    CreateUnlabeledEventJob.perform_now(@user.id, [@issue.id], unlabeled_at, @label.id, @label.name, @label.color)
    assert_equal 1, @issue.events.count
  end
end
