# typed: true
# frozen_string_literal: true

require "test_helper"
class PullRequestReviewThreadPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @assignee = create(:user)
    @org = create :organization, login: "acme", admin: @user
    @repo = create :repository, owner: @org, from_example: :rebase_pull_request
    @label = create :label, name: "Bug", repository: @repo
    @issue = create(:issue, user: @user, repository: @repo, title: "Quokka Hugs", body: "Sparkle")
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: @issue
    )

    review = @pull.reviews.create!(
      user: @user,
      head_sha: @pull.head_sha,
      body: "my review"
    )
    comment = create(:pull_request_review_comment, pull_request: @pull,
      user: @user,
      pull_request_review: review)
    review.comment!
    @thread = comment.pull_request_review_thread

    @repo_hook = create :hook, :web, installation_target: @repo, events: %w(*)
    @org_hook = create :hook, :org, installation_target: @org, events: %w(pull_request_review_thread)
  end

  context "v3" do
    test "works for resolved" do
      event = Hook::Event::PullRequestReviewThreadEvent.new(action: "resolved", thread_id: @thread.id, pull_request_id: @thread.pull_request_id, actor_id: @user)
      payload = Hook::Payload::PullRequestReviewThreadPayload.new event

      v3 = payload.to_hash

      assert_equal "resolved", v3[:action]
      assert_equal @pull.id, v3[:pull_request][:id]
      assert_equal @thread.async_to_deprecated_thread.sync.global_relay_id, v3[:thread][:node_id]
    end

    test "works for unresolved" do
      event = Hook::Event::PullRequestReviewThreadEvent.new(action: "unresolved", thread_id: @thread.id, pull_request_id: @thread.pull_request_id, actor_id: @user)
      payload = Hook::Payload::PullRequestReviewThreadPayload.new event

      v3 = payload.to_hash

      assert_equal "unresolved", v3[:action]
      assert_equal @pull.id, v3[:pull_request][:id]
      assert_equal @thread.async_to_deprecated_thread.sync.global_relay_id, v3[:thread][:node_id]
    end
  end
end
