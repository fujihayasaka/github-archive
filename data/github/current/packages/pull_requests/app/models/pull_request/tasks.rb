# typed: true
# frozen_string_literal: true

class PullRequest
  class Tasks
    def initialize(pull_request)
      @pull_request = pull_request
    end

    # All the task items related to the PullRequest
    def items
      @items ||= pr_body_items + comment_items + pr_review_comment_items
    end

    def pr_body_items
      @pull_request.task_list_summary.items.each { |item| item.permalink = @pull_request.permalink }
    end

    # Task list items from PullRequestReviewComment's
    def pr_review_comment_items
      @pull_request.review_comments.select { |c| c.task_list? }.map do |c|
        c.task_list_summary.items.each { |i| i.permalink = c.permalink }
      end.flatten
    end

    # Task list items from Pull Request comments
    def comment_items
      @pull_request.issue.comments.select { |c| c.task_list? }.map do |c|
        c.task_list_summary.items.each { |i| i.permalink = c.permalink }
      end.flatten
    end

    def complete_count
      items.count { |i| i.complete? }
    end

    def total_count
      items.count
    end

    def complete?
      complete_count == total_count
    end
  end
end
