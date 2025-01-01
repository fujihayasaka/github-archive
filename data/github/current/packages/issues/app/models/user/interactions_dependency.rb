# typed: true
# frozen_string_literal: true

module User::InteractionsDependency
  extend T::Helpers

  requires_ancestor { User }

  # Query batch size.
  BATCH_SIZE = 100_000

  # Generates the set of Issue IDs that the user has interacted with in some
  # fashion. The user is either the author of the issue or they have commented
  # on the issue.
  #
  # Returns a Set of Issue IDs.
  def interacted_issue_ids
    # the user is the author
    res = batch_ids { |previous_max_id| issue_ids_query(previous_max_id) }

    # the user has commented on an issue.
    res = res.merge(batch_ids { |previous_max_id| issue_comment_issue_ids_query(previous_max_id) })

    res
  end

  # Generates the set of PullRequest IDs that the user has interacted with in
  # some fashion. The user is either the author of the pull request or they
  # have commented on the pull request. The comment can be either a review
  # comment or a normal issue-style comment.
  #
  # Returns a Set of PullRequest IDs.
  def interacted_pull_request_ids
    # the user is the author
    res = batch_ids { |previous_max_id| pull_request_ids_query(previous_max_id) }

    # the user has a review comment on the pull request
    res = res.merge(batch_ids { |previous_max_id| pull_request_review_comments_pr_ids_query(previous_max_id) })

    # the user has a normal comment on the pull request
    res = res.merge(batch_ids { |previous_max_id| pull_request_regular_comments_pr_ids_query(previous_max_id) })

    res
  end

  private

  def issue_ids_query(previous_max_id)
    <<~SQL
      SELECT issues.id FROM issues
      WHERE issues.pull_request_id IS NULL
      AND issues.user_id = #{self.id}
      AND issues.id > #{previous_max_id}
      ORDER BY issues.id
      LIMIT #{BATCH_SIZE}
    SQL
  end

  def issue_comment_issue_ids_query(previous_max_id)
    <<~SQL
      SELECT issues.id FROM issues
      INNER JOIN issue_comments ON issue_comments.issue_id = issues.id
      WHERE issues.pull_request_id IS NULL
      AND issue_comments.user_id = #{self.id}
      AND issues.id > #{previous_max_id}
      GROUP BY issues.id
      ORDER BY issues.id
      LIMIT #{BATCH_SIZE}
    SQL
  end

  def pull_request_ids_query(previous_max_id)
    <<~SQL
      SELECT pull_requests.id FROM pull_requests
      WHERE pull_requests.user_id = #{self.id}
      AND pull_requests.id > #{previous_max_id}
      ORDER BY pull_requests.id
      LIMIT #{BATCH_SIZE}
    SQL
  end

  def pull_request_review_comments_pr_ids_query(previous_max_id)
    <<~SQL
      SELECT pull_request_review_comments.pull_request_id FROM pull_request_review_comments
      WHERE pull_request_review_comments.user_id = #{self.id}
      AND pull_request_review_comments.pull_request_id > #{previous_max_id}
      GROUP BY pull_request_review_comments.pull_request_id
      ORDER BY pull_request_review_comments.pull_request_id
      LIMIT #{BATCH_SIZE}
    SQL
  end

  def pull_request_regular_comments_pr_ids_query(previous_max_id)
    <<~SQL
      SELECT issues.pull_request_id FROM issues
      INNER JOIN issue_comments ON issue_comments.issue_id = issues.id
      WHERE issues.pull_request_id IS NOT NULL
      AND issue_comments.user_id = #{self.id}
      AND issues.pull_request_id > #{previous_max_id}
      GROUP BY issues.pull_request_id
      ORDER BY issues.pull_request_id
      LIMIT #{BATCH_SIZE}
    SQL
  end

  def batch_ids(&query_gen)
    previous_max_id = T.let(0, Integer)
    pull_request_ids = []
    loop do
      query = query_gen.call(previous_max_id)

      res = Issue.connection.select_values query

      pull_request_ids.concat res

      break if res.size < BATCH_SIZE
      previous_max_id = res.last
    end

    pull_request_ids.to_set
  end
end
