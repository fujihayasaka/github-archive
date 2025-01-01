# typed: true
# frozen_string_literal: true

require "github/linear_scale"
# Reponsible for weighting the impact of a contributions.  A Contribution can
# represent an opened issue, proposed pull request or a commit.
#
# Each contribution type is given an individual weight range that's distributed
# along a linear scale that's unique to each contribution type. This is because
# some contributions are considered more important than others.  For example,
# opening a Pull Request is worth more because it's considered to have more of
# an impact on a repository than opening an issue.
#
# The date a contribution happened also affects its weight.  A commit created
# today is worth more than a commit created last week.  We're also smart about
# ranking different types of contributions.  For example, an issue created today
# is worth more than a Pull Request created six months ago.
#
#    scorer = ContributionScorer.new(day_in_the_past)
#    scorer.score_issue(issue)
#    scorer.score_issues(issues)
#
class Contribution::Scorer
  ISSUE_MIN           = 0.1
  ISSUE_MAX           = 0.5

  COMMIT_MIN          = 1.0
  COMMIT_MAX          = 2.0

  PULL_REQUEST_MIN    = 2.0
  PULL_REQUEST_MAX    = 3.0

  ISSUE_COMMENTS_MIN = 1.0
  ISSUE_COMMENTS_MAX = 2.5

  attr_reader :domain

  def initialize(oldest_day, newest_day = Time.zone.today, weighted: true)
    @domain = [(Time.zone.today - newest_day).to_f, (Time.zone.today - oldest_day).to_f]
    @weighted = weighted
  end

  # Retrieve the combined score for a group of CommitContributions
  #
  # commits - An array of CommitContributions
  #
  # Returns a Float
  def score_commits(contributions)
    contributions.inject(0) { |m, c| m + score_commit(c) }
  end

  # Retrieve the combined score for a group of Issues
  #
  # issues - An array of Issues
  #
  # Returns a Float
  def score_issues(contributions)
    contributions.inject(0) { |m, c| m + score_issue(c) }
  end

  # Retrieve the combined score for a group of PullRequests
  #
  # pulls - An array of PullRequests
  #
  # Returns a Float
  def score_pull_requests(contributions)
    contributions.inject(0) { |m, c| m + score_pull_request(c) }
  end

  # Retrieve the combined score for a group of IssueComments
  #
  # comments - An array of IssueComments
  #
  # Returns a Float
  def score_issue_comments(contributions)
    contributions.inject(0) { |m, c| m + score_issue_comment(c) }
  end

  # Retrieve the score of a commit contribution.
  #
  # Commit contributions are slightly different from other types of contributions
  # because a single CommitContribution can represent multiple commits, therefore
  # we calculate the final score based on the commit count.
  #
  # Returns a Float
  def score_commit(contribution)
    score = commits_scale.call(recency_weighting(contribution.occurred_at))

    # Give extra credit for every commit beyond the first one
    # We do this so we're not "double" scoring the first commit
    if contribution.contributions_count - 1 > 0
      score += ((contribution.contributions_count - 1) * score)
    end

    score
  end

  # Retrieve the score of an issue which should always be between ISSUE_MIN and
  # ISSUE_MAX
  #
  # Returns a Float
  def score_issue(contribution)
    issues_scale.call(recency_weighting(contribution.occurred_at))
  end

  # Retrieve the score of a Pull Request which should always be between
  # PULL_REQUEST_MIN and PULL_REQUEST_MAX
  #
  # Returns a Float
  def score_pull_request(contribution)
    pull_requests_scale.call(recency_weighting(contribution.occurred_at))
  end

  # Retrieve the score of a Issue Comment which should always be between
  # ISSUE_COMMENTS_MIN and ISSUE_COMMENTS_MAX
  #
  # Returns a Float
  def score_issue_comment(contribution)
    issue_comments_scale.call(recency_weighting(contribution.occurred_at))
  end

  private

  def pull_requests_scale
    GitHub::LinearScale.scale! @domain, [find_scale(PULL_REQUEST_MAX), find_scale(PULL_REQUEST_MIN)]
  end

  def issue_comments_scale
    GitHub::LinearScale.scale! @domain, [find_scale(ISSUE_COMMENTS_MAX), find_scale(ISSUE_COMMENTS_MIN)]
  end

  def issues_scale
    GitHub::LinearScale.scale! @domain, [find_scale(ISSUE_MAX), find_scale(ISSUE_MIN)]
  end

  def commits_scale
    GitHub::LinearScale.scale! @domain, [find_scale(COMMIT_MAX), find_scale(COMMIT_MIN)]
  end

  def recency_weighting(date)
    @weighted ? Time.zone.today - date.to_date : 0
  end

  def find_scale(const)
    @weighted ? const : 1.0
  end
end
