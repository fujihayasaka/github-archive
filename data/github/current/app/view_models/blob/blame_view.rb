# typed: false
# frozen_string_literal: true

class Blob::BlameView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

  # We're scoping the recency range to 2 years. Commits older than 2 years look the same.
  # This makes it easier to differentiate between more recent commits.
  RECENCY_TIME_RANGE = 2.years

  # Manually-adjusted percentual limits of each color heat range, that is,
  # range 1 is for commits as old as 0% to 0.7% of the repository age,
  # range 2 is for commits between 0.7% to 1.4%, etc.
  HEAT_RANGE_LIMITS = [0, 0.7, 1.4, 3, 4.9, 8.4, 14, 23, 38, 62, 100]

  # Range of consecutive lines changed in a commit.
  LineRange = Struct.new(:commit, :lines, :reblame_path) do
    def reblamable?
      reblame_path.present?
    end
  end

  attr_reader :blame

  def range
    @range ||= (1..10).map { |ix| "#{ix}" }
  end

  def days_in_range
    @days_in_range ||= [now - repository.created_at, RECENCY_TIME_RANGE].min
  end

  # Calculates a commit "heat age" from its authoring date (relative to
  # repository age, capped in 2 years)
  #
  # Returns a number from 1 (newest) to 10 (oldest)
  def heat(commit)
    days_in_commit = now - commit.authored_date

    commit_age_percent = 100 * days_in_commit / days_in_range

    range = HEAT_RANGE_LIMITS.index { |limit| commit_age_percent < limit }
    (range || 10).clamp(1, 10)
  end

  def commit_has_comments?(oid)
    commit_oids_with_comments.include?(oid)
  end

  def commit_oids_with_comments
    @commit_oids_with_comments ||= Set.new(repository.commit_comments.select("DISTINCT commit_id").pluck(:commit_id))
  end

  # Group runs of consecutive lines changed in the same commit.
  #
  # Returns an Array of range objects with `commit` and `lines` properties.
  def commit_line_ranges
    @lines ||= begin
      ranges = []
      blame.each do |lineno, old_lineno, commit, text, reblame_path|
        if ranges.empty? || commit.oid != ranges.last.commit.oid
          ranges << LineRange.new(commit, [], reblame_path)
        end
        ranges.last.lines << [lineno, old_lineno, commit, text]
      end
      ranges
    end
  end

  def repository
    blame.repository
  end

  private

  def now
    @now ||= Time.new
  end
end
