# typed: true
# frozen_string_literal: true

require "test_helper"

class DeleteExpiredNotificationSummariesJobTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, :minimal, owner: @user)

    @issues = create_list(:issue, 20, repository: @repo, user: @user)

    @to_delete = Timecop.freeze(4.months.ago) do
      @issues.take(10).map do |issue|
        NotificationSummary.create(list: @repo, thread: issue).id
      end
    end

    @referenced = Timecop.freeze(4.months.ago) do
      @issues.drop(10).take(3).map do |issue|
        summary = NotificationSummary.create(list: @repo, thread: issue)
        Newsies::NotificationEntry.insert(@user.id, summary, reason: "subscribed", event_time: 1.minute.ago)

        summary.id
      end
    end

    @saved = Timecop.freeze(4.months.ago) do
      @issues.drop(13).take(2).map do |issue|
        summary = NotificationSummary.create(list: @repo, thread: issue)
        Newsies::SavedNotificationEntry.save(user_id: @user.id, summary_id: summary.id, list: summary.newsies_list, thread: summary.newsies_thread)

        summary.id
      end
    end

    @recent = Timecop.freeze(2.months.ago) do
      @issues.drop(15).take(5).map do |issue|
        NotificationSummary.create(list: @repo, thread: issue).id
      end
    end
  end

  test "it deletes expired unreferenced summaries" do
    Timecop.freeze do
      DeleteExpiredNotificationSummariesJob.perform_now
    end

    assert_equal 10, NotificationSummary.count
    assert_equal 0, NotificationSummary.where(id: @to_delete).count
    assert_equal 3, NotificationSummary.where(id: @referenced).count
    assert_equal 2, NotificationSummary.where(id: @saved).count
    assert_equal 5, NotificationSummary.where(id: @recent).count
  end

  test "it deletes expired unreferenced summaries from given offset" do
    Timecop.freeze do
      DeleteExpiredNotificationSummariesJob.perform_now(offset_id: @to_delete.drop(4).first)
    end

    assert_equal 15, NotificationSummary.count
    assert_equal 0, NotificationSummary.where(id: @to_delete.drop(5)).count
    assert_equal 5, NotificationSummary.where(id: @to_delete.take(5)).count
    assert_equal 3, NotificationSummary.where(id: @referenced).count
    assert_equal 2, NotificationSummary.where(id: @saved).count
    assert_equal 5, NotificationSummary.where(id: @recent).count
  end
end
