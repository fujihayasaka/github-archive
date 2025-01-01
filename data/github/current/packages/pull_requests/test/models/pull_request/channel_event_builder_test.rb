# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestChannelEventBuilderTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo)
  end

  context "sidebar_updated" do
    context "when FF is on" do
      context "when associated_updates is empty" do
        test "includes sidebar_updated", feature_enabled: :sidebar_event_updates do
          payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
          assert_equal payload, { event_updates: { sidebar_updated: true, timeline_updated: true, git_updated: false } }
        end
      end

      context "when associated_updates is not empty" do
        test "does not include sidebar_updated", feature_enabled: :sidebar_event_updates do
          payload = PullRequest::ChannelEventBuilder.new(@pull, { "reviewers_updated" => true }).build_payload
          assert_equal payload, { event_updates: { :timeline_updated => true, "reviewers_updated" => true, :git_updated => false } }
        end
      end
    end

    context "when FF is off" do
      context "when associated_updates is empty" do
        test "does not include sidebar_updated or associated_updates", feature_disabled: :sidebar_event_updates do
          payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
          assert_equal payload, { event_updates: { timeline_updated: true, git_updated: false } }
        end
      end

      context "when associated_updates is not empty" do
        test "does not include sidebar_updated or associated_updates", feature_disabled: :sidebar_event_updates do
          payload = PullRequest::ChannelEventBuilder.new(@pull, { "reviewers_updated" => true }).build_payload
          assert_equal payload, { event_updates: { timeline_updated: true, git_updated: false } }
        end
      end
    end
  end

  context "body_updated" do
    context "when sidebar_updated FF is on" do
      context "when link_events_updates FF is on" do
        context "when PR body is updated" do
          test "does not include sidebar_updated and includes body_updated" do
            GitHub.flipper[:sidebar_event_updates].enable(@pull.repository)
            GitHub.flipper[:links_event_updates].enable(@pull.repository)
            @pull.issue.reload
            @pull.issue.update(compressed_body: "change to body")

            payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
            assert_equal payload, { event_updates: { body_updated: true, git_updated: false } }
          end

          context "when associated_updates is not empty" do
            test "does not include sidebar_updated but includes associated updates and body_updated", feature_disabled: :sidebar_event_updates do
              GitHub.flipper[:sidebar_event_updates].enable(@pull.repository)
              GitHub.flipper[:links_event_updates].enable(@pull.repository)
              @pull.issue.reload
              @pull.issue.update(compressed_body: "change to body")

              payload = PullRequest::ChannelEventBuilder.new(@pull, { "reviewers_updated" => true }).build_payload
              assert_equal payload, { event_updates: { :body_updated => true, :git_updated => false, "reviewers_updated" => true } }
            end
          end
        end

        context "when PR body is NOT updated" do
          test "includes sidebar_updated and does not include body_updated" do
            GitHub.flipper[:sidebar_event_updates].enable(@pull.repository)
            GitHub.flipper[:links_event_updates].enable(@pull.repository)
            @pull.issue.reload

            payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
            assert_equal payload, { event_updates: { sidebar_updated: true, timeline_updated: true, git_updated: false } }
          end

          context "when associated_updates is not empty" do
            test "does not include sidebar_updated but includes associated updates", feature_disabled: :sidebar_event_updates do
              GitHub.flipper[:sidebar_event_updates].enable(@pull.repository)
              GitHub.flipper[:links_event_updates].enable(@pull.repository)
              @pull.issue.reload

              payload = PullRequest::ChannelEventBuilder.new(@pull, { "reviewers_updated" => true }).build_payload
              assert_equal payload, { event_updates: { :timeline_updated => true, :git_updated => false, "reviewers_updated" => true } }
            end
          end
        end
      end

      context "when link_events_updates FF is off" do
        context "when PR body is updated" do
          test "includes sidebar_updated and body_updated" do
            GitHub.flipper[:sidebar_event_updates].enable(@pull.repository)
            GitHub.flipper[:links_event_updates].disable(@pull.repository)
            @pull.issue.reload
            @pull.issue.update(compressed_body: "change to body")

            payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
            assert_equal payload, { event_updates: { sidebar_updated: true, body_updated: true, git_updated: false } }
          end

          context "when associated_updates is not empty" do
            test "does not include sidebar_updated but includes body_updated and associated updates", feature_disabled: :sidebar_event_updates do
              GitHub.flipper[:sidebar_event_updates].enable(@pull.repository)
              GitHub.flipper[:links_event_updates].disable(@pull.repository)
              @pull.issue.reload
              @pull.issue.update(compressed_body: "change to body")

              payload = PullRequest::ChannelEventBuilder.new(@pull, { "reviewers_updated" => true }).build_payload
              assert_equal payload, { event_updates: { :body_updated => true, :git_updated => false, "reviewers_updated" => true } }
            end
          end
        end

        context "when PR body is NOT updated" do
          test "includes sidebar_updated and does not include body_updated" do
            GitHub.flipper[:sidebar_event_updates].enable(@pull.repository)
            GitHub.flipper[:links_event_updates].disable(@pull.repository)
            @pull.issue.reload

            payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
            assert_equal payload, { event_updates: { sidebar_updated: true, timeline_updated: true, git_updated: false } }
          end

          context "when associated_updates is not empty" do
            test "does not include sidebar_updated or body_updated but includes associated updates", feature_disabled: :sidebar_event_updates do
              GitHub.flipper[:sidebar_event_updates].enable(@pull.repository)
              GitHub.flipper[:links_event_updates].disable(@pull.repository)
              @pull.issue.reload

              payload = PullRequest::ChannelEventBuilder.new(@pull, { "reviewers_updated" => true }).build_payload
              assert_equal payload, { event_updates: { :timeline_updated => true, :git_updated => false, "reviewers_updated" => true } }
            end
          end
        end
      end
    end

    context "when sidebar_updated FF is off" do
      context "when link_events_updates FF is on" do
        context "when PR body is updated" do
          test "does not include sidebar_updated and includes body_updated" do
            GitHub.flipper[:sidebar_event_updates].disable(@pull.repository)
            GitHub.flipper[:links_event_updates].enable(@pull.repository)
            @pull.issue.reload
            @pull.issue.update(compressed_body: "change to body")

            payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
            assert_equal payload, { event_updates: { body_updated: true, git_updated: false } }
          end
        end

        context "when PR body is NOT updated" do
          test "does not include either sidebar_updated or body_updated" do
            GitHub.flipper[:sidebar_event_updates].disable(@pull.repository)
            GitHub.flipper[:links_event_updates].enable(@pull.repository)
            @pull.issue.reload

            payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
            assert_equal payload, { event_updates: { timeline_updated: true, git_updated: false } }
          end
        end
      end

      context "when link_events_updates FF is off" do
        context "when PR body is updated" do
          test "does not include sidebar_updated and includes body_updated" do
            GitHub.flipper[:sidebar_event_updates].disable(@pull.repository)
            GitHub.flipper[:links_event_updates].disable(@pull.repository)
            @pull.issue.reload
            @pull.issue.update(compressed_body: "change to body")

            payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
            assert_equal payload, { event_updates: { body_updated: true, git_updated: false } }
          end
        end

        context "when PR body is NOT updated" do
          test "does not include either sidebar_updated or body_updated" do
            GitHub.flipper[:sidebar_event_updates].disable(@pull.repository)
            GitHub.flipper[:links_event_updates].disable(@pull.repository)
            @pull.issue.reload

            payload = PullRequest::ChannelEventBuilder.new(@pull, {}).build_payload
            assert_equal payload, { event_updates: { timeline_updated: true, git_updated: false } }
          end
        end
      end
    end

    test "does not include sidebar_updated if labels_updated is true", feature_enabled: :sidebar_event_updates do
      payload = PullRequest::ChannelEventBuilder.new(@pull, { "labels_updated" => true }).build_payload
      assert_nil payload.dig(:event_updates, :sidebar_updated)
    end

    test "does not include sidebar_updated if milestone_updated is true", feature_enabled: :sidebar_event_updates do
      payload = PullRequest::ChannelEventBuilder.new(@pull, { "milestone_updated" => true }).build_payload
      assert_nil payload.dig(:event_updates, :sidebar_updated)
    end
  end
end
