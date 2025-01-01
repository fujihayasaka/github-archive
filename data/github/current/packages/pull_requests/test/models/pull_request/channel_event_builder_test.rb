# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestChannelEventBuilderTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
  end

  context "title_updated" do
    test "includes title_updated when title is updated" do
      @pull.issue.update(title: "change to title")

      payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
      assert payload.dig(:event_updates, :title_updated)
    end

    test "does not include title_updated when title is not updated" do
      @pull.issue.update(compressed_body: "change to body")

      payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
      assert_nil payload.dig(:event_updates, :title_updated)
    end

    test "includes title_updated when merged_at is updated" do
      @pull.update(merged_at: Time.now - 1.day)

      payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
      assert payload.dig(:event_updates, :title_updated)
    end

    test "includes title_updated when work_in_progress is updated" do
      @pull.update(work_in_progress: true)

      payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
      assert payload.dig(:event_updates, :title_updated)
    end
  end

  context "git_updated" do
    test "includes git_updated when base_sha is updated" do
      @pull.update(base_sha: "change to base_sha")

      payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
      assert payload.dig(:event_updates, :git_updated)
    end

    test "includes git_updated when head_sha is updated" do
      @pull.update(head_sha: "change to head_sha")

      payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
      assert payload.dig(:event_updates, :git_updated)
    end
  end

  context "sidebar_updated" do
    context "when associated_updates is empty" do
      test "includes sidebar_updated if skip_full_sidebar_updates flag is off" do
        disable_feature_flag(:skip_full_sidebar_updates)

        payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
        assert payload.dig(:event_updates, :sidebar_updated)
      end

      test "does not include sidebar_updated if skip_full_sidebar_updates flag is on" do
        enable_feature_flag(:skip_full_sidebar_updates)

        payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
        refute payload.dig(:event_updates, :sidebar_updated)
      end
    end

    context "when associated_updates is not empty" do
      test "does not include sidebar_updated if labels_updated is true" do
        payload = PullRequest::ChannelEventBuilder.new(@pull, { labels_updated: true }).build_payload
        assert_nil payload.dig(:event_updates, :sidebar_updated)
      end

      test "does not include sidebar_updated if milestone_updated is true" do
        payload = PullRequest::ChannelEventBuilder.new(@pull, { milestone_updated: true }).build_payload
        assert_nil payload.dig(:event_updates, :sidebar_updated)
      end

      test "does not include sidebar_updated if assignees_updated is true" do
        payload = PullRequest::ChannelEventBuilder.new(@pull, { assignees_updated: true }).build_payload
        assert_nil payload.dig(:event_updates, :sidebar_updated)
      end

      test "does not include sidebar_updated if projects_updated is true" do
        payload = PullRequest::ChannelEventBuilder.new(@pull, { projects_updated: true }).build_payload
        assert_nil payload.dig(:event_updates, :sidebar_updated)
      end

      test "does not include sidebar_updated if reviewers_updated is true" do
        payload = PullRequest::ChannelEventBuilder.new(@pull, { reviewers_updated: true }).build_payload
        assert_nil payload.dig(:event_updates, :sidebar_updated)
      end
    end
  end

  context "body_updated" do
    context "when PR body is updated" do
      test "does not include timeline_updated" do
        @pull.issue.update(compressed_body: "change to body")

        payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
        assert payload.dig(:event_updates, :body_updated)
        assert_nil payload.dig(:event_updates, :timeline_updated)
      end

      context "when links_event_updates FF is on" do
        test "does not include sidebar_updated and includes body_updated", skip_if_feature_disabled: :links_event_updates  do
          @pull.issue.update(compressed_body: "change to body")

          payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
          assert payload.dig(:event_updates, :body_updated)
          assert_nil payload.dig(:event_updates, :sidebar_updated)
        end

        context "when associated_updates is not empty" do
          test "does not include sidebar_updated but includes associated updates and body_updated", skip_if_feature_disabled: :links_event_updates  do
            @pull.issue.update(compressed_body: "change to body")

            payload = PullRequest::ChannelEventBuilder.new(@pull, { reviewers_updated: true }).build_payload
            assert payload.dig(:event_updates, :body_updated)
            assert payload.dig(:event_updates, :reviewers_updated)
            assert_nil payload.dig(:event_updates, :sidebar_updated)
          end
        end
      end

      context "when links_event_updates FF is off" do
        test "includes sidebar_updated and body_updated", skip_if_feature_enabled: :links_event_updates do
          @pull.issue.update(compressed_body: "change to body")

          payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
          assert payload.dig(:event_updates, :body_updated)
          assert payload.dig(:event_updates, :sidebar_updated)
        end

        context "when associated_updates is not empty" do
          test "does not include sidebar_updated but includes body_updated", skip_if_feature_enabled: :links_event_updates do
            @pull.issue.update(compressed_body: "change to body")

            payload = PullRequest::ChannelEventBuilder.new(@pull, { reviewers_updated: true }).build_payload
            assert payload.dig(:event_updates, :reviewers_updated)
            assert payload.dig(:event_updates, :body_updated)
            assert_nil payload.dig(:event_updates, :sidebar_updated)
          end
        end
      end
    end

    context "when PR body is NOT updated" do
      test "includes timeline_updated" do
        payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
        assert_nil payload.dig(:event_updates, :body_updated)
        assert payload.dig(:event_updates, :timeline_updated)
      end

      context "when links_event_updates FF is on" do
        test "includes sidebar_updated and does not include body_updated", skip_if_feature_enabled: :links_event_updates do
          payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
          assert_nil payload.dig(:event_updates, :body_updated)
          assert payload.dig(:event_updates, :sidebar_updated)
        end

        context "when associated_updates is not empty" do
          test "does not include sidebar_updated but includes associated updates", skip_if_feature_enabled: :links_event_updates do
            payload = PullRequest::ChannelEventBuilder.new(@pull, { reviewers_updated: true }).build_payload
            assert_nil payload.dig(:event_updates, :body_updated)
            assert_nil payload.dig(:event_updates, :sidebar_updated)
            assert payload.dig(:event_updates, :reviewers_updated)
          end
        end
      end

      context "when links_event_updates FF is off" do
        test "includes sidebar_updated and does not include body_updated", skip_if_feature_enabled: :links_event_updates do
          payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
          assert payload.dig(:event_updates, :sidebar_updated)
          assert_nil payload.dig(:event_updates, :body_updated)
        end

        context "when associated_updates is not empty" do
          test "does not include sidebar_updated or body_updated but includes associated updates", skip_if_feature_enabled: :links_event_updates do
            payload = PullRequest::ChannelEventBuilder.new(@pull, { reviewers_updated: true }).build_payload
            assert_nil payload.dig(:event_updates, :sidebar_updated)
            assert_nil payload.dig(:event_updates, :body_updated)
            assert payload.dig(:event_updates, :reviewers_updated)
          end
        end
      end
    end
  end
end
