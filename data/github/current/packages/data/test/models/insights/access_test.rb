# typed: true
# frozen_string_literal: true
require "test_helper"

class Insights::AccessTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "owner", plan: "large"
  end
  context "#enabled?" do
    test "true when the insights_enabled feature flag is flipped" do
      GitHub.flipper[:insights_enabled].enable(@owner)
      assert Insights::Access.enabled?(@owner)
    end

    test "false when the insights_enabled feature flag is not flipped" do
      GitHub.flipper[:insights_enabled].disable(@owner)
      refute Insights::Access.enabled?(@owner)
    end
  end

  context "#publish_enabled?" do
    test "true when the insights_publish_enabled feature flag is flipped" do
      GitHub.flipper[:insights_publish_enabled].enable(@owner)
      assert Insights::Access.publish_enabled?(@owner)
    end

    test "false when the insights_publish_enabled feature flag is not flipped" do
      GitHub.flipper[:insights_publish_enabled].disable(@owner)
      refute Insights::Access.publish_enabled?(@owner)
    end
  end

  context "#enabled_staging?" do
    test "true when the insights_enabled_staging feature flag is flipped" do
      GitHub.flipper[:insights_enabled_staging].enable(@owner)
      assert Insights::Access.enabled_staging?(@owner)
    end

    test "false when the insights_enabled_staging feature flag is not flipped" do
      GitHub.flipper[:insights_enabled_staging].disable(@owner)
      refute Insights::Access.enabled_staging?(@owner)
    end
  end

  context "#pull_requests_publish_enabled?" do
    test "true when the insights_pull_requests_publish feature flag is flipped" do
      GitHub.flipper[:insights_pull_requests_publish].enable(@owner)
      assert Insights::Access.pull_requests_publish_enabled?(@owner)
    end

    test "false when the insights_pull_requests_publish feature flag is not flipped" do
      GitHub.flipper[:insights_pull_requests_publish].disable(@owner)
      refute Insights::Access.pull_requests_publish_enabled?(@owner)
    end
  end

  context "#pull_request_reviews_publish_enabled?" do
    test "true when the insights_pull_request_reviews_publish feature flag is enabled" do
      GitHub.flipper[:insights_pull_request_reviews_publish].enable(@owner)
      assert Insights::Access.pull_request_reviews_publish_enabled?(@owner)
    end

    test "false when the insights_pull_request_reviews_publish feature flag is not enabled" do
      GitHub.flipper[:insights_pull_request_reviews_publish].disable(@owner)
      refute Insights::Access.pull_request_reviews_publish_enabled?(@owner)
    end
  end

  context "#assignments_publish_enabled?" do
    test "true when the insights_assignments_publish feature flag is flipped" do
      GitHub.flipper[:insights_assignments_publish].enable(@owner)
      assert Insights::Access.assignments_publish_enabled?(@owner)
    end

    test "false when the insights_assignments_publish feature flag is not flipped" do
      GitHub.flipper[:insights_assignments_publish].disable(@owner)
      refute Insights::Access.assignments_publish_enabled?(@owner)
    end
  end

  context "#draft_assignments_publish_enabled?" do
    test "true when the insights_draft_assignments_publish feature flag is flipped" do
      GitHub.flipper[:insights_draft_assignments_publish].enable(@owner)
      assert Insights::Access.draft_assignments_publish_enabled?(@owner)
    end

    test "false when the insights_draft_assignments_publish feature flag is not flipped" do
      GitHub.flipper[:insights_draft_assignments_publish].disable(@owner)
      refute Insights::Access.draft_assignments_publish_enabled?(@owner)
    end
  end

  context "#users_publish_enabled?" do
    if GitHub.enterprise?
      test "false on GitHub Enterprise" do
        refute Insights::Access.users_publish_enabled?(@owner)
      end
    end

    if !GitHub.enterprise?
      test "true when not GitHub Enterprise" do
        assert Insights::Access.users_publish_enabled?(@owner)
      end
    end
  end
end
