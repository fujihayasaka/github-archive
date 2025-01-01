# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeGroupStatTest < GitHub::TestCase
  test_datetime = DateTime.new(2020, 9, 7, 3, 52)

  fixtures do
    @repo = create(:repository, :has_merge_queue)
    @queue = @repo.merge_queue_for(branch: @repo.default_branch)
    @days_of_backdata = 30
    @sum_of_merged_counts = 0

    sequence = [1, 3, 5]
    sequence_index = 0
    some_number = lambda {
      sequence_index += 1
      sequence[sequence_index % sequence.count]
    }

    day_range = (0..@days_of_backdata - 1)
    day_range.each do |days_ago|
      (0..some_number.call).each do
        pull_requests_merged_count = some_number.call
        create(:merge_group_stat,
               repository: @repo,
               base_branch: @repo.default_branch,
               pull_requests_merged_count: pull_requests_merged_count,
               first_pr_queued_at: test_datetime,
               created_at: test_datetime - days_ago.days,
               updated_at: test_datetime,
              )
        @sum_of_merged_counts += pull_requests_merged_count
      end
    end
  end

  context "valid histogram data" do
    test "validate merge_counts_by_day" do
      counts_by_day = MergeGroupStat.merge_counts_by_day(queue: @queue,
                                                         base_branch: @repo.default_branch,
                                                         start_date: test_datetime.to_date - @days_of_backdata.days,
                                                         end_date: test_datetime.to_date)
      assert counts_by_day.keys.to_set.count == @days_of_backdata
      assert counts_by_day.values.sum == @sum_of_merged_counts
    end
  end
end
