# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadActionsPushPayloadTest < GitHub::TestCase
  fixtures do
    @holman  = create(:user, login: "holman", email: "holman@github.com")
    @defunkt = create(:user, login: "defunkt", email: "defunkt@github.com")

    @repo = create :repository, owner: @holman
  end

  setup do
    example_repo :post_receive_job_test, @repo

    @event = Hook::Event::PushEvent.new({
        repo: @repo,
        before: "c1800491d95c42b4e96fb83f31fe8d9230c62907",
        after: "63611721afd41f58f801d66e543d8288b4c5eb44",
        ref: "refs/heads/master",
        pusher: @defunkt,
      })
  end

  context "git_only" do
    context "when include_git_data is false" do
      test "returns empty payload" do
        payload = Hook::Payload::ActionsPushPayload.new @event, include_git_data: false

        git_only = payload.git_only

        assert_empty git_only
      end
    end

    context "when include_git_data is true" do
      test "returns payload with only git data" do
        payload = Hook::Payload::ActionsPushPayload.new @event, include_git_data: true

        git_only = payload.git_only

        refute git_only.has_key?(:repository)
        refute git_only.has_key?(:pusher)
        refute git_only.has_key?(:sender)

        assert git_only.has_key?(:created)
        assert git_only.has_key?(:deleted)
        assert git_only.has_key?(:forced)
        assert git_only.has_key?(:base_ref)
        assert git_only.has_key?(:compare)
        assert git_only.has_key?(:commits)
        assert git_only.has_key?(:head_commit)
      end

      test "does not include diffs" do
        payload = Hook::Payload::ActionsPushPayload.new @event, include_git_data: true

        git_only = payload.git_only

        assert_equal 2, git_only[:commits].count
        git_only[:commits].each do |commit|
          refute_includes commit.keys, :added
          refute_includes commit.keys, :removed
          refute_includes commit.keys, :modified
        end
      end

      test "limits number of commits in output" do
        metadata = {
          message: "test",
          committer: { name: "Test", email: "test@example.com" },
        }
        head = @event.after
        Hook::Payload::ActionsPushPayload.stub_const(:COMMIT_PAYLOAD_LIMIT, 1) do
          2.times do |i|
            head = @repo.commits.create(metadata, head) do |files|
              files.add(i.to_s, "")
            end.oid
          end
          @event.after = head

          payload = Hook::Payload::ActionsPushPayload.new @event, include_git_data: true
          git_only = payload.git_only
          assert_equal Hook::Payload::ActionsPushPayload::COMMIT_PAYLOAD_LIMIT, git_only[:commits].count
          assert_equal @event.after, git_only[:commits].last[:id]
        end
      end
    end
  end
end
