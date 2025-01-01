# typed: true
# frozen_string_literal: true

module Spam
  class AdditionalUserInfo

    attr_reader :user

    def initialize(user)
      @user = user
    end

    # Public: The empty results hash
    def empty_results
      {
        user: nil,
        issues: [],
        issue_comments: [],
        gist_comments: [],
        commit_comments: [],
        repositories: [],
        gists: [],
        no_items_present: true,
      }
    end

    def results
      results = empty_results

      if user.present?
        issues          = user.issues.order("created_at DESC").includes(:repository).limit(4)
        issue_comments  = user.issue_comments.order("created_at DESC").includes(:issue, :repository).limit(6)
        gist_comments   = user.gist_comments.order("created_at DESC").includes(:gist).limit(6)
        commit_comments = user.commit_comments.order("created_at DESC").includes(:repository).limit(6)
        repositories    = user.repositories.order("created_at DESC").limit(4)
        gists           = user.gists.order("created_at DESC").limit(6)

        results[:user] = user
        results[:issues] = issues
        results[:issue_comments] = issue_comments
        results[:gist_comments] = gist_comments
        results[:commit_comments] = commit_comments
        results[:repositories] = repositories
        results[:gists] = gists
        results[:no_items_present] = [issues, issue_comments, gist_comments,
                                      commit_comments, repositories, gists].all? { |list| list.empty? }
      end

      results
    end
  end
end
