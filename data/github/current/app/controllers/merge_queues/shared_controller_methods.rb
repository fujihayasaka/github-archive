# typed: true
# frozen_string_literal: true

module MergeQueues::SharedControllerMethods
  ENTRIES_PER_PAGE = 25
  GROUPS_PER_PAGE = 3
  RECENT_MERGE_HISTOGRAM_DAYS = 30

  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { ApplicationController }
  requires_ancestor { IRepositoryController }

  private

  def up_next_entries_for_display
    entries = if merge_queue.requires_deployments_before_merging?
      grouped_entries.ungrouped_entries
    else
      all_entries
    end

    entries.paginate(
      page: current_page,
      per_page: params[:per_page].presence || ENTRIES_PER_PAGE,
    )
  end

  def recent_merges_histogram
    today = Date.today

    histogram = {}
    (0...RECENT_MERGE_HISTOGRAM_DAYS).each do |days_to_subtract|
      date = today - days_to_subtract.days
      histogram[date] = { date: date, count: 0, days_ago: (today - date).to_f }
    end

    counts_by_day = T.let(MergeGroupStat.merge_counts_by_day(
      queue: merge_queue,
      base_branch: merge_queue.branch,
      start_date: today - RECENT_MERGE_HISTOGRAM_DAYS.days,
      end_date: today,
    ), T::Hash[Date, Integer])

    counts_by_day.each do |date_count_pair|
      date, count = date_count_pair
      histogram[date] = { date: date, count: count, days_ago: (today - date).to_f }
    end

    histogram.values.sort_by { |day| day[:date] }
  end

  def merge_queue_required
    return render_404 unless current_repository.merge_queue_enabled?
    return render_404 unless merge_queue
  end

  def merge_queue
    return @merge_queue if defined?(@merge_queue)

    branch = params[:merge_queue_branch] || current_repository.default_branch
    @merge_queue = current_repository.merge_queue_for(branch: branch)
  end

  sig { returns(T.nilable(MergeQueues::Group[MergeQueueEntry])) }
  def active_merge_group
    grouped_entries.active_group
  end

  sig { returns(MergeQueues::Group::PartitionResult[MergeQueueEntry]) }
  memoize def grouped_entries
    configuration = MergeQueues.configuration_for(merge_queue)
    MergeQueues::Group.partition(configuration:, entries: all_entries)
  end

  sig { returns(T::Array[MergeQueueEntry]) }
  memoize def all_entries
    entries = merge_queue.entries.to_a

    MergeQueue.prefill_associations(
      entries: entries,
      repository: current_repository,
      users: [owner, current_user].uniq,
    )

    entries
  end
end
