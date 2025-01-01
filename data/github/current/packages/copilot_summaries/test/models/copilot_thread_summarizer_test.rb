# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotThreadSummarizerTest < GitHub::TestCase
  include ResiliencyHelpers

  setup do
    GitHub.flipper[:copilot_summary_ga].disable
  end

  context ".can_be_summarized?" do
    test "returns false for anonymous user" do
      refute CopilotThreadSummarizer.can_be_summarized?(
        viewer: nil,
        copilot_user: nil,
        body_length: CopilotThreadSummarizer::MIN_CHAR_COUNT_FOR_SUMMARIZING,
      )
    end

    test "returns false for authenticated viewer with Copilot Enterprise access and beta features disabled when summaries feature is not publicly shipped" do
      viewer = build(:user)

      copilot_user = Copilot::User.new(viewer)
      Copilot::User.any_instance.expects(:has_ce_access?).returns(true)
      Copilot::User.any_instance.expects(:has_cb_access?).never
      Copilot::User.any_instance.expects(:has_ci_access?).never
      Copilot::User.any_instance.expects(:beta_features_github_chat_enabled?).returns(false)

      refute CopilotThreadSummarizer.can_be_summarized?(
        viewer: viewer,
        copilot_user: copilot_user,
        body_length: CopilotThreadSummarizer::MIN_CHAR_COUNT_FOR_SUMMARIZING,
      )
    end

    test "returns false when user does not have Copilot business seat" do
      viewer = build(:user)

      copilot_user = Copilot::User.new(viewer)
      Copilot::User.any_instance.expects(:has_ce_access?).returns(false)
      Copilot::User.any_instance.expects(:has_cb_access?).returns(false)
      Copilot::User.any_instance.expects(:has_ci_access?).returns(false)
      Copilot::User.any_instance.expects(:beta_features_github_chat_enabled?).never

      refute CopilotThreadSummarizer.can_be_summarized?(
        viewer: viewer,
        copilot_user: copilot_user,
        body_length: CopilotThreadSummarizer::MIN_CHAR_COUNT_FOR_SUMMARIZING,
      )
    end

    test "returns true when body length is long enough to need a summary, get_comment_bodies_length is specified, and there are no comments" do
      viewer = build(:user)

      copilot_user = Copilot::User.new(viewer)
      Copilot::User.any_instance.expects(:has_ce_access?).returns(false)
      Copilot::User.any_instance.expects(:has_cb_access?).returns(false)
      Copilot::User.any_instance.expects(:has_ci_access?).returns(true)
      Copilot::User.any_instance.expects(:beta_features_github_chat_enabled?).never

      assert CopilotThreadSummarizer.can_be_summarized?(
        viewer: viewer,
        copilot_user: copilot_user,
        body_length: CopilotThreadSummarizer::MIN_CHAR_COUNT_FOR_SUMMARIZING,
        get_comment_bodies_length: -> { 0 },
      )
    end

    test "returns false when body length is too short to need a summary and get_comment_bodies_length is not specified" do
      viewer = build(:user)

      copilot_user = Copilot::User.new(viewer)
      Copilot::User.any_instance.expects(:has_ce_access?).never
      Copilot::User.any_instance.expects(:has_cb_access?).never
      Copilot::User.any_instance.expects(:has_ci_access?).never

      refute CopilotThreadSummarizer.can_be_summarized?(
        viewer: viewer,
        copilot_user: copilot_user,
        body_length: CopilotThreadSummarizer::MIN_CHAR_COUNT_FOR_SUMMARIZING - 1,
      )
    end

    test "returns false when body and comment body lengths combined are too short to need a summary" do
      viewer = build(:user)

      copilot_user = Copilot::User.new(viewer)
      Copilot::User.any_instance.expects(:has_ce_access?).never
      Copilot::User.any_instance.expects(:has_cb_access?).never
      Copilot::User.any_instance.expects(:has_ci_access?).never

      refute CopilotThreadSummarizer.can_be_summarized?(
        viewer: viewer,
        copilot_user: copilot_user,
        body_length: CopilotThreadSummarizer::MIN_CHAR_COUNT_FOR_SUMMARIZING - 2,
        get_comment_bodies_length: -> { 1 },
      )
    end

    test "gracefully degrades when Copilot cluster is unavailable" do
      viewer = create(:user)
      copilot_user = Copilot::User.new(viewer)
      prevent_connections_to(ApplicationRecord::Copilot) do
        refute CopilotThreadSummarizer.can_be_summarized?(
          viewer: viewer,
          copilot_user: copilot_user,
          body_length: CopilotThreadSummarizer::MIN_CHAR_COUNT_FOR_SUMMARIZING,
          get_comment_bodies_length: -> { 0 },
        )
      end
    end
  end

  context "has_copilot_summaries_access?" do
    test "returns false if the user is not logged in" do
      refute CopilotThreadSummarizer.has_copilot_summaries_access?(viewer: nil)
    end

    test "returns false if the user is not a Copilot user" do
      Copilot::Public::User.any_instance.expects(:has_ce_access?).returns(false)
      Copilot::Public::User.any_instance.expects(:has_cb_access?).returns(false)
      Copilot::Public::User.any_instance.expects(:has_ci_access?).returns(false)

      refute CopilotThreadSummarizer.has_copilot_summaries_access?(viewer: build(:user))
    end

    test "returns true if ga flag is enabled and user has copilot access" do
      viewer = build(:user)
      viewer.expects(:feature_enabled?).with(any_parameters).returns(true).at_least_once
      Copilot::Public::User.any_instance.expects(:has_copilot_access?).returns(true)

      assert CopilotThreadSummarizer.has_copilot_summaries_access?(viewer: viewer)
    end

    test "returns true if user has Copilot Individual access" do
      Copilot::Public::User.any_instance.expects(:has_ce_access?).returns(false)
      Copilot::Public::User.any_instance.expects(:has_cb_access?).returns(false)
      Copilot::Public::User.any_instance.expects(:has_ci_access?).returns(true)

      assert CopilotThreadSummarizer.has_copilot_summaries_access?(viewer: build(:user))
    end

    context "with Copilot Enterprise access" do
      test "returns false if user has access but beta features are disabled" do
        Copilot::Public::User.any_instance.expects(:has_ce_access?).returns(true)
        Copilot::Public::User.any_instance.expects(:has_cb_access?).never
        Copilot::Public::User.any_instance.expects(:has_ci_access?).never
        Copilot::Public::User.any_instance.expects(:beta_features_github_chat_enabled?).returns(false)

        refute CopilotThreadSummarizer.has_copilot_summaries_access?(viewer: build(:user))
      end

      test "returns true if user has access and beta features are enabled" do
        Copilot::Public::User.any_instance.expects(:has_ce_access?).returns(true)
        Copilot::Public::User.any_instance.expects(:has_cb_access?).never
        Copilot::Public::User.any_instance.expects(:has_ci_access?).never
        Copilot::Public::User.any_instance.expects(:beta_features_github_chat_enabled?).returns(true)

        assert CopilotThreadSummarizer.has_copilot_summaries_access?(viewer: build(:user))
      end
    end

    context "with Copilot Business access" do
      test "returns false if user has access but beta features are disabled" do
        Copilot::Public::User.any_instance.expects(:has_ce_access?).returns(false)
        Copilot::Public::User.any_instance.expects(:has_cb_access?).returns(true)
        Copilot::Public::User.any_instance.expects(:has_ci_access?).never
        Copilot::Public::User.any_instance.expects(:beta_features_github_chat_enabled?).returns(false)

        refute CopilotThreadSummarizer.has_copilot_summaries_access?(viewer: build(:user))
      end

      test "returns true if user has access and beta features are enabled" do
        Copilot::Public::User.any_instance.expects(:has_ce_access?).returns(false)
        Copilot::Public::User.any_instance.expects(:has_cb_access?).returns(true)
        Copilot::Public::User.any_instance.expects(:has_ci_access?).never
        Copilot::Public::User.any_instance.expects(:beta_features_github_chat_enabled?).returns(true)

        assert CopilotThreadSummarizer.has_copilot_summaries_access?(viewer: build(:user))
      end
    end
  end
end
