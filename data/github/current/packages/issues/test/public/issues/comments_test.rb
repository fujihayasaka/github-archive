# typed: true
# frozen_string_literal: true

require "test_helper"

class CommentsTest < GitHub::TestCase
  fixtures do
    @comment = create(:issue_comment, body: "This is a comment")
  end

  test "update comment body" do
    assert_all_features_preloaded do
      Issues::Comments.update_comment(@comment, "This is a new comment", @comment.user)
    end

    assert_equal @comment.body, "This is a new comment"
  end

  test "check queries to collab primary and replicas" do
    if TestEnv.test_with_all_emus?
      collab_primary_count = GitHub.flipper[:issue_update_comment_body_use_collab_replica].enabled? ? 0 : 1
      collab_replicas_count = GitHub.flipper[:issue_update_comment_body_use_collab_replica].enabled? ? 1 : 0
      if TestEnv.test_in_multitenancy_mode?
        collab_replicas_count = 3
      end
    elsif TestEnv.enterprise?
      collab_primary_count = 0
      collab_replicas_count = 0
    else
      collab_primary_count = GitHub.flipper[:issue_update_comment_body_use_collab_replica].enabled? ? 0 : 3
      collab_replicas_count = GitHub.flipper[:issue_update_comment_body_use_collab_replica].enabled? ? 3 : 0
    end

    primary_clusters_and_counts = {
      ApplicationRecord::Collab => collab_primary_count,
    }

    replica_clusters_and_counts = {
      ApplicationRecord::Collab => collab_replicas_count,
    }

    assert_query_count_against_primary(clusters_and_counts: primary_clusters_and_counts) do
      assert_query_count_against_replicas(clusters_and_counts: replica_clusters_and_counts) do
        Issues::Comments.update_comment(@comment, "This is a new comment", @comment.user)
      end
    end

    assert_equal @comment.body, "This is a new comment"
  end

  def assert_all_features_preloaded
    VexiSubscriber.collector.reset
    VexiSubscriber.collector.enable
    FlipperSubscriber.collector.reset
    FlipperSubscriber.collector.enable

    yield

    VexiSubscriber.collector.disable
    FlipperSubscriber.collector.disable
    tested = (VexiSubscriber.tested_features.keys + FlipperSubscriber.tested_features.keys).map(&:to_s)
    preloaded = (VexiSubscriber.preloaded_features + FlipperSubscriber.preloaded_features).to_a

    tested_and_not_preloaded = tested - preloaded
    assert_empty tested_and_not_preloaded.sort, <<-MSG
      These features were checked but weren't preloaded.
    MSG
  end
end
