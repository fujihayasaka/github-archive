# typed: true
# frozen_string_literal: true

class Api::Discussions < Api::App

  # Get a single Discussion
  get "/repositories/:repository_id/discussions/:discussion_number", operation_id: "discussions/get" do
    repo = find_repo_with_discussions_enabled!

    discussion = repo.discussions
      .filter_spam_for(current_user)
      .with_number(params[:discussion_number]).first

    control_access :show_discussion,
      repo: repo,
      resource: discussion,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver :discussion_hash, discussion
  end

  # List discussions for a repository
  get "/repositories/:repository_id/discussions", operation_id: "discussions/list-for-repo" do
    repo = find_repo_with_discussions_enabled!

    control_access :list_discussions,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    discussions = repo.discussions
      .filter_spam_for(current_user)
      .oldest_first
      .includes(:reactions, :category, :labels, :user)
    discussions = paginate_rel(discussions)

    deliver :discussion_hash, discussions
  end

  # List comments for a discussion
  get "/repositories/:repository_id/discussions/:discussion_number/comments", operation_id: "discussions/list-discussion-comments" do
    repo = find_repo_with_discussions_enabled!

    discussion = repo.discussions
      .filter_spam_for(current_user)
      .with_number(params[:discussion_number]).first

    deliver_error! 404 unless discussion

    control_access :show_discussion,
      repo: repo,
      resource: discussion,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    comments = discussion.comments
      .filter_spam_for(current_user)
      .includes(:reactions, :user, :repository)
    comments = paginate_rel(comments)

    deliver :discussion_comment_hash, comments
  end

  private

  def find_repo_with_discussions_enabled!
    repo = find_repo!
    deliver_error!(410, message: "Discussions are disabled for this repo") unless repo.discussions_on?
    repo
  end
end
