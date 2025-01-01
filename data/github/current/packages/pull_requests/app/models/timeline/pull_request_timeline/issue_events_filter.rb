# typed: true
# frozen_string_literal: true

# Internal: Filters issue event placeholders from Pull Requests
class Timeline::PullRequestTimeline::IssueEventsFilter
  attr_reader :pull_request, :viewer

  def initialize(issue_events_placeholders, pull_request_commits_placeholders, viewer:, pull_request:,
                 filter_closed_if_preceded_by_merged: false)
    @issue_events_placeholders = issue_events_placeholders
    @pull_request_commits_placeholders = pull_request_commits_placeholders
    @filter_closed_if_preceded_by_merged = filter_closed_if_preceded_by_merged
    @pull_request = pull_request
    @viewer = viewer
  end

  def call
    merge_event_seen = T.let(false, T::Boolean)

    sorted_issue_events_placeholders.reject do |placeholder|
      case placeholder.event_name
      when "merged"
        merge_event_seen = true
        false # do not reject
      when "closed"
        filter_closed_if_preceded_by_merged && merge_event_seen
      when "referenced"
        commit_part_of_pull_request?(placeholder)
      end
    end
  end

  private

  attr_reader :issue_events_placeholders, :pull_request_commits_placeholders,
              :filter_closed_if_preceded_by_merged

  # Internal: Filter commit references to this pull request from its own commits.
  #
  # Return Boolean
  def commit_part_of_pull_request?(placeholder)
    commit_oids.include?(placeholder.commit_oid)
  end

  def commit_oids
    return @commit_oids if defined?(@commit_oids)

    commits = pull_request_commits_placeholders.map(&:oid)
    commits.push(pull_request.merge_commit_sha) if pull_request.merged?

    @commit_oids = Set.new(commits)
  end

  def sorted_issue_events_placeholders
    return @sorted_issue_events_placeholders if defined?(@sorted_issue_events_placeholders)

    @sorted_issue_events_placeholders = issue_events_placeholders.sort_by(&:sort_key)
  end
end
