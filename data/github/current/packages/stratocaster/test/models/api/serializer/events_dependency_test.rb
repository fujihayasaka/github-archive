# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"
require "test_helpers/spokesd"

class EventSerializersTest < Api::SerializerTestCase
  fixtures do
    @user = create(:user)
  end

  context "#stratocaster_event_hash" do
    test "gets avatar url" do
      event = Stratocaster::Event.new
      event.sender = @user
      event_hash = stratocaster_event(event)
      refute_nil actor_hash = event_hash["actor"]
      assert_equal "#{GitHub.alambic_avatar_url}/u/#{@user.id}?", actor_hash["avatar_url"]
    end
  end

  context "#conduit_event_hash" do
    test "gets avatar url" do
      repo = create(:repository, owner: @user)
      twirp_item = build(:twirp_conduit_starred_repository_feed_item, repository: repo)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "#{GitHub.alambic_avatar_url}/u/#{@user.id}?", event_hash["actor"]["avatar_url"]
    end

    test "gets gravatar_id" do
      repo = create(:repository, owner: @user)
      twirp_item = build(:twirp_conduit_starred_repository_feed_item, repository: repo)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "", event_hash["actor"]["gravatar_id"]
    end

    test "adds org info when repo owner is an org" do
      org = create(:enterprise_linked_organization, login: "bookish-potato")
      repo = create(:repository, owner: org)
      org.add_member(@user)

      twirp_item = build(:twirp_conduit_starred_repository_feed_item, repository: repo)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "#{GitHub.api_url}/orgs/#{org.login}", event_hash["org"]["url"]
    end

    test "no org key when repo owner is not an org" do
      repo = create(:repository, owner: @user)
      twirp_item = build(:twirp_conduit_starred_repository_feed_item, repository: repo)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_nil event_hash["org"]
    end

    test "gets correct repo name" do
      repo = create(:repository, owner: @user)
      twirp_item = build(:twirp_conduit_starred_repository_feed_item, repository: repo)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "#{@user.login}/#{repo.name}", event_hash["repo"]["name"]
    end

    test "event is public if repo visibility is public" do
      repo = create(:repository, owner: @user)
      twirp_item = build(:twirp_conduit_starred_repository_feed_item, repository: repo)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal true, event_hash["public"]
    end

    test "event is not public if repo visibility is private" do
      repo = create(:private_repository, owner: @user)
      twirp_item = build(:twirp_conduit_starred_repository_feed_item, repository: repo)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal false, event_hash["public"]
    end

    test "created_at return the time as a string" do
      repo = create(:repository, owner: @user)
      twirp_item = build(:twirp_conduit_starred_repository_feed_item, :with_created_at, repository: repo)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_instance_of String, event_hash["created_at"]
    end

    context "WatchEvent" do
      test "gets correct type" do
        repo = create(:repository, owner: @user)
        twirp_item = build(:twirp_conduit_starred_repository_feed_item, repository: repo)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "WatchEvent", event_hash["type"]
      end

      test "gets correct payload" do
        repo = create(:repository, owner: @user)
        twirp_item = build(:twirp_conduit_starred_repository_feed_item, repository: repo)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal event_hash["payload"]["action"], "started"
      end
    end

    context "IssueCommentEvent" do
      test "gets correct type" do
        repo = create(:repository, owner: @user)
        twirp_item = build(:twirp_conduit_issue_comment_feed_item)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "IssueCommentEvent", event_hash["type"]
      end

      test "gets correct payload" do
        issue = create(:issue)
        comment = create(:issue_comment, issue: issue)
        twirp_item = build(:twirp_conduit_issue_comment_feed_item, issue:, comment:)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "created", event_hash["payload"]["action"]
        assert_equal issue.id, event_hash["payload"]["issue"]["id"]
        assert_equal comment.id, event_hash["payload"]["comment"]["id"]
      end

      test "Pull request comments are also IssueCommentEvents" do
        repo = create(:repository, owner: @user, from_example: :review_comment_source)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
        comment = create(:issue_comment, issue: pull_request.issue)

        twirp_item = build(:twirp_conduit_pull_request_comment_feed_item, pull_request:, comment:)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "IssueCommentEvent", event_hash["type"]
        assert_equal "created", event_hash["payload"]["action"]
        assert_equal pull_request.issue.id, event_hash["payload"]["issue"]["id"]
        assert_equal comment.id, event_hash["payload"]["comment"]["id"]
      end

      test "returns nil when pull request has no issue" do
        repo = create(:repository, owner: @user, from_example: :review_comment_source)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
        comment = create(:issue_comment)

        twirp_item = build(:twirp_conduit_pull_request_comment_feed_item, pull_request:, comment:)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first

        assert_nil event
      end
    end

    context "ForkEvent" do
      test "gets correct type" do
        repo = create(:repository, owner: @user)
        twirp_item = build(
          :twirp_conduit_repository_feed_item,
          repository: repo,
          action: Conduit::TwirpHelper.forked_action
        )
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)
        assert_equal "ForkEvent", event_hash["type"]
      end

      test "gets correct payload" do
        repo = create(:repository, owner: @user)
        twirp_item = build(
          :twirp_conduit_repository_feed_item,
          repository: repo,
          action: Conduit::TwirpHelper.forked_action
        )
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal repo.id, event_hash["payload"]["forkee"]["id"]
      end
    end

    context "IssuesEvent" do
      test "gets correct type" do
        issue = create(:issue)
        twirp_item = build(:twirp_conduit_issue_feed_item, :created, issue:)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "IssuesEvent", event_hash["type"]
      end

      test "gets correct payload for opened event" do
        issue = create(:issue)
        twirp_item = build(:twirp_conduit_issue_feed_item, :created, issue:)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)
        assert_equal "opened", event_hash["payload"]["action"]
        assert_equal issue.id, event_hash["payload"]["issue"]["id"]
      end

      test "gets correct payload for reopened event" do
        issue = create(:issue)
        twirp_item = build(:twirp_conduit_issue_feed_item, :reopened, issue:)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "reopened", event_hash["payload"]["action"]
        assert_equal issue.id, event_hash["payload"]["issue"]["id"]
      end

      test "gets correct payload for closed event" do
        issue = create(:issue)
        twirp_item = build(:twirp_conduit_issue_feed_item, :closed, issue:)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "closed", event_hash["payload"]["action"]
        assert_equal issue.id, event_hash["payload"]["issue"]["id"]
      end

      test "gets correct payload for assigned event" do
        issue = create(:issue)
        twirp_item = build(:twirp_conduit_issue_feed_item, :assigned, issue:)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "assigned", event_hash["payload"]["action"]
        assert_equal issue.id, event_hash["payload"]["issue"]["id"]
      end
    end

    context "CommitCommentEvent" do
      test "gets correct type" do
        twirp_item = build(:twirp_conduit_commit_comment_feed_item)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)
        assert_equal "CommitCommentEvent", event_hash["type"]
      end

      test "gets correct payload for opened event" do
        comment = create(:commit_comment)
        twirp_item = build(:twirp_conduit_commit_comment_feed_item, comment: comment)
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)
        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "created", event_hash["payload"]["action"]
        assert_equal comment.id, event_hash["payload"]["comment"]["id"]
      end
    end

    context "MemberEvent" do
      test "gets correct type" do
        event = build(:member_add_to_repository)
        event_hash = conduit_event(event)

        assert_equal "MemberEvent", event_hash["type"]
      end

      test "gets correct payload" do
        member = create(:user)
        event = build(:member_add_to_repository, member: member)
        event_hash = conduit_event(event)

        assert_equal member.id, event_hash["payload"]["member"]["id"]
        assert_equal "added", event_hash["payload"]["action"]
      end
    end

    context "PublicEvent" do
      test "gets correct type" do
        event = build(:repository_feed_item, :published)
        event_hash = conduit_event(event)

        assert_equal "PublicEvent", event_hash["type"]
      end

      test "gets correct payload" do
        event = build(:repository_feed_item, :published)
        event_hash = conduit_event(event)
        empty_payload = {}

        assert_equal empty_payload, event_hash["payload"]
      end
    end

    context "PullRequestEvent" do
      test "gets correct type" do
        repo = create(:repository, owner: @user, from_example: :review_comment_source)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
        event = build(:pull_request_feed_item, :created, subject: pull_request)
        event_hash = conduit_event(event)

        assert_equal "PullRequestEvent", event_hash["type"]
      end

      test "gets correct payload when opened" do
        repo = create(:repository, owner: @user, from_example: :review_comment_source)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
        event = build(:pull_request_feed_item, :created, subject: pull_request)
        event_hash = conduit_event(event)

        assert_equal "opened", event_hash["payload"]["action"]
        assert_equal pull_request.number, event_hash["payload"]["number"]
        assert_equal pull_request.id, event_hash["payload"]["pull_request"]["id"]
      end

      test "gets correct payload when closed" do
        repo = create(:repository, owner: @user, from_example: :review_comment_source)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
        event = build(:pull_request_feed_item, :closed, subject: pull_request)
        event_hash = conduit_event(event)

        assert_equal "closed", event_hash["payload"]["action"]
        assert_equal pull_request.number, event_hash["payload"]["number"]
        assert_equal pull_request.id, event_hash["payload"]["pull_request"]["id"]
      end

      test "gets correct payload when reopened" do
        repo = create(:repository, owner: @user, from_example: :review_comment_source)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
        event = build(:pull_request_feed_item, :reopened, subject: pull_request)
        event_hash = conduit_event(event)

        assert_equal "reopened", event_hash["payload"]["action"]
        assert_equal pull_request.number, event_hash["payload"]["number"]
        assert_equal pull_request.id, event_hash["payload"]["pull_request"]["id"]
      end
    end

    context "PullRequestReviewEvent" do
      test "gets correct type" do
        repo = create(:repository, owner: @user, from_example: :review_comment_source)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
        pull_request_review = create(:pull_request_review, pull_request: pull_request, repository: repo)

        twirp_item = build(
          :twirp_conduit_pull_request_review_feed_item,
          pull_request_review: pull_request_review,
          action: Conduit::TwirpHelper.created_action
        )
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "PullRequestReviewEvent", event_hash["type"]
      end

      test "gets correct payload when created" do
        repo = create(:repository, owner: @user, from_example: :review_comment_source)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
        pull_request_review = create(:pull_request_review, pull_request: pull_request, repository: repo)

        twirp_item = build(
          :twirp_conduit_pull_request_review_feed_item,
          pull_request_review: pull_request_review,
          action: Conduit::TwirpHelper.created_action
        )

        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)
        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "created", event_hash["payload"]["action"]
        assert_equal pull_request.id, event_hash["payload"]["pull_request"]["id"]
        assert_equal pull_request_review.id, event_hash["payload"]["review"]["id"]
      end
    end

    context "PullRequestReviewCommentEvent" do
      test "gets correct type" do
        repo = create(:repository, owner: @user, from_example: :review_comment_source)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
        pull_request_review_comment = create(:pull_request_review_comment, pull_request: pull_request, repository: repo)

        twirp_item = build(
          :twirp_conduit_pull_request_review_comment_feed_item,
          pull_request_review_comment: pull_request_review_comment,
          action: Conduit::TwirpHelper.published_action
        )
        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "PullRequestReviewCommentEvent", event_hash["type"]
      end

      test "gets correct payload when created" do
        repo = create(:repository, owner: @user, from_example: :review_comment_source)
        pull_request = create(:pull_request, :with_mergeable_head, repository: repo, user: @user)
        pull_request_review_comment = create(:pull_request_review_comment, pull_request: pull_request, repository: repo)

        twirp_item = build(
          :twirp_conduit_pull_request_review_comment_feed_item,
          pull_request_review_comment: pull_request_review_comment,
          action: Conduit::TwirpHelper.published_action
        )

        feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)
        event = feed.items.first
        event_hash = conduit_event(event)

        assert_equal "created", event_hash["payload"]["action"]
        assert_equal pull_request.id, event_hash["payload"]["pull_request"]["id"]
        assert_equal pull_request_review_comment.id, event_hash["payload"]["comment"]["id"]
      end
    end
  end

  context "PushEvent" do
    test "gets correct type" do
      event = build(:push_event_item)
      event_hash = conduit_event(event)

      assert_equal "PushEvent", event_hash["type"]
    end

    test "gets correct payload" do
      repository = create(:repository, from_example: :simple)
      before = "2c6363c328126bdee83e9f8dd55ad1db3a2aa160"
      after = "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"
      push = create :push, repository: repository, before: before, after: after, ref: "master"

      event = build(:push_event_item, subject: push)
      event_hash = conduit_event(event)

      commits = push.commits
      expected_commit_payload = commits.map do |commit|
        {
          "sha" => commit.oid,
          "author" => { "email" => commit.author_email, "name" => commit.author_name },
          "message" => commit.message,
          "distinct" => false,
          "url" => "#{GitHub.api_url}/repos/#{repository.name_with_display_owner}/commits/#{commit.oid}",
        }
      end

      assert_equal push.id, event_hash["payload"]["push_id"]
      assert_equal repository.id, event_hash["payload"]["repository_id"]
      assert_equal expected_commit_payload, event_hash["payload"]["commits"]
    end
  end

  context "CreateEvent" do
    test "gets correct type for new branch" do
      enable_feature_flag(:conduit_push_events)

      repository = create(:repository, from_example: :simple)
      before = GitHub::NULL_OID
      after = "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"
      push = create(:push, repository: repository, before: before, after: after, ref: "master")

      twirp_item = build(:twirp_conduit_push_event_feed_item, push: push)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "CreateEvent", event_hash["type"]
    end

    test "gets correct payload" do
      enable_feature_flag(:conduit_push_events)

      repository = create(:repository, from_example: :simple, description: "test")
      before = GitHub::NULL_OID
      after = "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"
      push = create(:push, repository: repository, before: before, after: after, ref: "master")

      twirp_item = build(:twirp_conduit_push_event_feed_item, push: push)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal push.ref, event_hash["payload"]["ref"]
      assert_equal push.pusher.type, event_hash["payload"]["pusher_type"]
      assert_equal repository.description, event_hash["payload"]["repository"]["description"]
    end
  end

  context "DeleteEvent" do
    test "gets correct type for new branch" do
      enable_feature_flag(:conduit_push_events)

      repository = create(:repository, from_example: :simple)
      after = GitHub::NULL_OID
      before = "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"
      push = create(:push, repository: repository, before: before, after: after, ref: "master")

      twirp_item = build(:twirp_conduit_push_event_feed_item, push: push)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "DeleteEvent", event_hash["type"]
    end

    test "gets correct payload" do
      enable_feature_flag(:conduit_push_events)

      repository = create(:repository, from_example: :simple, description: "test")
      before = GitHub::NULL_OID
      after = "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"
      push = create(:push, repository: repository, before: before, after: after, ref: "master")

      twirp_item = build(:twirp_conduit_push_event_feed_item, push: push)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)

      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal push.ref, event_hash["payload"]["ref"]
      assert_equal push.pusher.type, event_hash["payload"]["pusher_type"]
      assert_equal "branch", event_hash["payload"]["ref_type"]
    end
  end

  context "SponsorshipEvent" do
    test "gets correct type" do
      event = build(:user_feed_item, :sponsored)
      event_hash = conduit_event(event)

      assert_equal "SponsorshipEvent", event_hash["type"]
    end

    test "gets correct payload" do
      maintainer = create(:user, :sponsorable)
      sponsor = create(:credit_card_user, :verified, :sponsorable, plan_subscription: create(:billing_plan_subscription))
      event = build(:user_feed_item, :sponsored, subject: maintainer, actor: sponsor)
      event_hash = conduit_event(event)

      assert_equal maintainer.id, event_hash["payload"]["maintainer_id"]
      assert_equal sponsor.id, event_hash["payload"]["sponsor_id"]
      assert_equal maintainer.id, event_hash["payload"]["target"]["id"]
      assert_equal true, event_hash["public"] # SponsorshipEvents are always public
    end
  end

  context "ReleaseEvent" do
    test "gets correct type" do
      twirp_item = build(:twirp_conduit_release_feed_item)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)
      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "ReleaseEvent", event_hash["type"]
    end

    test "gets correct payload" do
      repo = create(:repository, from_example: :simple, owner: @user)
      release = create(:release, repository: repo, author: repo.owner)
      twirp_item = build(:twirp_conduit_release_feed_item, release: release)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)
      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "published", event_hash["payload"]["action"]
      assert_equal release.id, event_hash["payload"]["release"]["id"]
      assert_equal false, event_hash["payload"]["release"]["is_short_description_html_truncated"]
    end
  end

  context "GollumEvent" do
    test "gets correct type" do
      Spokesd.enable_spokesd

      repo = create(:repository, owner: @user)
      repo.initialize_wiki(repo.owner)
      wiki = repo.unsullied_wiki
      example_repo :wiki, wiki

      twirp_item = build(:twirp_conduit_wiki_push_feed_item, repo: repo)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: user)
      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "GollumEvent", event_hash["type"]
    end

    test "gets correct payload" do
      Spokesd.enable_spokesd

      repo = create(:repository, owner: @user)
      repo.initialize_wiki(repo.owner)
      wiki = repo.unsullied_wiki
      example_repo :wiki, wiki

      twirp_item = build(:twirp_conduit_wiki_push_feed_item, repo: repo)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)
      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "a" * 40, event_hash["payload"]["pages"].last["sha"]
      assert_equal "published", event_hash["payload"]["pages"].last["action"]
      assert_match "/", event_hash["payload"]["pages"].first["html_url"]
    end
  end

  context "DiscussionEvent" do
    test "gets correct type" do
      twirp_item = build(:twirp_conduit_discussion_feed_item)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)
      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "DiscussionEvent", event_hash["type"]
    end

    test "gets correct payload" do
      discussion = create(:discussion)
      twirp_item = build(:twirp_conduit_discussion_feed_item, discussion:)
      feed = build(:conduit_feed, twirp_items: [twirp_item], user: @user)
      event = feed.items.first
      event_hash = conduit_event(event)

      assert_equal "created", event_hash["payload"]["action"]
      assert_equal discussion.id, event_hash["payload"]["discussion"]["id"]
    end
  end
  context "#repo_hash" do
    test "returns an empty hash when repo is nil" do
      assert_equal({}, repo(nil))
    end

    test "returns correct hash for a valid repository" do
      repo = create(:repository, owner: @user)

      expected_url = "#{GitHub.api_url}/repos/#{repo.owner_display_login}/#{repo.name}"
      expected_hash = {
        "id" => repo.id,
        "name" => "#{repo.owner_display_login}/#{repo.name}",
        "url" => expected_url
      }
      assert_equal expected_hash, repo(repo)
    end
  end
end
