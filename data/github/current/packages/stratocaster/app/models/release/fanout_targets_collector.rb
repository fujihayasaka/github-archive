# typed: true
# frozen_string_literal: true

class Release::FanoutTargetsCollector
  STATS_PREFIX = "release.fanout"

  def initialize(release)
    @release = release
    @batched_distributions = {}
  end

  def targets
    return @targets if defined?(@targets)

    start_time = GitHub::Dogstats.monotonic_time

    target_ids = release_author_follower_ids.uniq

    GitHub.dogstats.count("#{STATS_PREFIX}.total", target_ids.count, tags: [])

    time_elapsed = GitHub::Dogstats.duration(start_time)

    GlobalInstrumenter.instrument("release.fanout_targets_collected", {
      release: release,
      repository: repository,
      author: author,
      total_targets: target_ids.count,
      total_commit_author_followers: 0,
      total_release_author_followers: release_author_follower_ids.count,
      total_stargazers: 0,
      time_elapsed: time_elapsed,
    })

    @targets = target_ids
  ensure
    @batched_distributions.each do |name, value|
      GitHub.dogstats.distribution(
        "release.fanout.#{name}.time",
        value,
        tags: []
      )
    end
  end

  private

  attr_reader :release

  delegate :repository, :author, to: :release

  def release_author_follower_ids
    return @release_author_follower_ids if defined?(@release_author_follower_ids)

    ids = record_distribution("release_author_followers") do
      author.followers.not_suspended.not_spammy.pluck(:user_id)
    end

    GitHub.dogstats.count("#{STATS_PREFIX}.release_author_followers", ids.count, tags: [])

    @release_author_follower_ids = ids
  end

  def record_distribution(name)
    start_time = GitHub::Dogstats.monotonic_time
    results = yield
    elapsed = GitHub::Dogstats.duration(start_time)
    @batched_distributions[name] = elapsed
    results
  end
end
