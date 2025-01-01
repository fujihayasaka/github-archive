# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

class Release::FindPreviousRelease
  BATCH_SIZE = 10
  MAX_TAGS = 50

  sig { params(release: Release).returns(T.nilable(Release)) }
  def self.for(release)
    new(release).previous_release
  end

  sig { params(release: Release).void }
  def initialize(release)
    @release = release
    @tags_fetched_limit_reached = false
  end

  sig { returns(T.nilable(Release)) }
  def previous_release
    return @previous_release if defined?(@previous_release)

    start_time = GitHub::Dogstats.monotonic_time
    found_release = find_previous_release
    time_elapsed = GitHub::Dogstats.duration(start_time)

    GlobalInstrumenter.instrument("release.previous_release_fetched", {
      release: release,
      previous_release: found_release,
      repository: repository,
      tags_fetched_limit_reached: @tags_fetched_limit_reached,
      time_elapsed: time_elapsed,
    })

    @previous_release = found_release
  end

  private

  sig { returns(Release) }
  attr_reader :release

  delegate :repository, to: :release

  sig { params(start_commitish: T.nilable(String), tags_fetched: Integer).returns(T.nilable(Release)) }
  def find_previous_release(start_commitish = release.current_target, tags_fetched = 0)
    if tags_fetched >= MAX_TAGS
      @tags_fetched_limit_reached = true
      return
    end

    tag_names = BATCH_SIZE.times.inject([start_commitish]) do |list, _curr|
      begin
        tag_name = repository.rpc.describe("#{list.last}^1")
        list << tag_name.gsub!(Release::SearchTags::GIT_DESCRIBE_SUFFIX_REGEX, "")
      rescue GitRPC::ObjectMissing
        break list
      end
    end

    candidate_tags = tag_names[1..-1]
    return if candidate_tags.empty?

    found_release = Release.where(repository: repository, tag_name: candidate_tags).last

    if found_release.nil?
      find_previous_release(candidate_tags.last, tags_fetched + BATCH_SIZE)
    else
      found_release
    end
  end
end
