# typed: true
# frozen_string_literal: true

class Stafftools::RecentComments
  extend AuditLogHelper

  def self.for_user(user)
    comments = []

    comments.concat(public_comments(DiscussionComment, user).preload(:repository))
    comments.concat(public_comments(Issue, user).preload(:repository))
    comments.concat(public_comments(IssueComment, user).includes(:issue).preload(:repository))
    comments.concat(public_comments(PullRequestReviewComment, user).preload(:repository))
    comments.concat(public_comments(CommitComment, user).preload(:repository))
    comments.concat(GistComment.public_scope.where(user: user).order(created_at: :desc).limit(25).to_a)

    comments.sort_by(&:created_at).reverse.first(25)
  end

  def self.public_comments(base_type, user)
    scope = base_type.where(user: user).order(created_at: :desc)

    repo_ids = scope.pluck(:repository_id, :created_at).map(&:first).uniq
    public_repo_ids = Repository.where(public: true, id: repo_ids).pluck(:id)

    scope.where(repository_id: public_repo_ids).limit(25)
  end

  def self.minimized_comment_count(user, viewer)
    phrase = "action:*.minimize_comment user:#{user.login}"
    if driftwood_ade_query?(viewer)
      phrase = <<~KQL
        webevents
        | where action in ("user.minimize_comment", "staff.minimize_comment")
        | where user == "#{user.login}"
      KQL
    end
    begin
      Timeout.timeout(Audit::Driftwood::QUERY_TIMEOUT) do
        query = Audit::Driftwood::Query.new_stafftools_query(
          phrase: phrase,
          current_user: user,
        )
        query.execute.total
      end
    rescue Timeout::Error
      -1
    end
  end
end
