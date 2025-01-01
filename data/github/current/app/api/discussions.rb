# typed: true
# frozen_string_literal: true

class Api::Discussions < Api::App
  # Get a single Discussion
  get "/repositories/:repository_id/discussions/:discussion_number", operation_id: "discussions/get" do
    repo = find_repo!

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
    repo = find_repo!

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
end
