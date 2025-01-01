# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class NotificationsSerializerTest < Api::SerializerTestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user  = create :user
    @repo  = create :repository
    @issue = create :issue

    # Subscribe to a thread
    assert_predicate GitHub.newsies.subscribe_to_thread(@user, @repo, @issue, "manual"), :success?
    @sub     = GitHub.newsies.subscription_status(@user, @repo, @issue)
    @api_url = GitHub.api_url
  end

  context "#newsies_subscription_hash" do
    context "with a :summary key in the options hash" do
      test "summary attributes are included in the output" do
        # Adding a minimal stub for summary.  The only attribute being leveraged
        # in this serializer is the :id key.
        summary = { id: 1 }
        output  = serialize_hash_method(:newsies_subscription_hash, @sub, summary: summary)

        assert_equal "#{@api_url}/notifications/threads/#{summary[:id]}", output["thread_url"]
        assert_equal "#{@api_url}/notifications/threads/#{summary[:id]}/subscription", output["url"]
      end
    end

    context "with a :list key in the options hash" do
      test "list/repo attributes are included in the output" do
        output          = serialize_hash_method(:newsies_subscription_hash, @sub, list: @repo)

        assert_equal "#{@api_url}/repos/#{@repo.name_with_owner}", output["repository_url"]
        assert_equal "#{@api_url}/repos/#{@repo.name_with_owner}/subscription", output["url"]
      end

      test "created_at return nil when subscription is not valid?" do
        @sub.stubs(:valid?).returns(false)
        output  = serialize_hash_method(:newsies_subscription_hash, @sub, list: @repo)

        assert_nil output["created_at"]
      end
    end

    context "both :list and :summary keys are passed in the options hash" do
      test "summary takes precedence" do
        # Adding a minimal stub for summary.  The only attribute being leveraged
        # in this serializer is the :id key.
        summary = { id: 1 }
        output  = serialize_hash_method(:newsies_subscription_hash, @sub, list: @repo, summary: summary)

        assert_equal "#{@api_url}/notifications/threads/#{summary[:id]}", output["thread_url"]
        assert_equal "#{@api_url}/notifications/threads/#{summary[:id]}/subscription", output["url"]
        assert_nil output["repository_url"]
      end
    end
  end

  context "#rollup_summary_hash" do
    context "repository advisory" do
      test "returns frozen title for removed PVR author" do
        pvr_advisory = create(:accepted_pvd_repo_advisory)
        pvr_submitter = pvr_advisory.author
        pvr_advisory.remove_collaborator(pvr_submitter)

        updated_title = pvr_advisory.title + " (updated)"
        pvr_advisory.update(title: updated_title)

        repos = {}
        repos[pvr_advisory.repository.id.to_s] = pvr_advisory.repository
        summary = NotificationSummary.fetch_and_update!(pvr_advisory.repository, pvr_advisory, pvr_advisory)

        hash = serialize_hash_method(:rollup_summary_hash, summary.to_summary_hash, repos: repos,
          current_user: pvr_submitter).with_indifferent_access

        assert_equal pvr_advisory.frozen_title, hash[:subject][:title]
        refute_equal updated_title, hash[:subject][:title]
      end

      test "returns current title for active collaborator" do
        pvr_advisory = create(:accepted_pvd_repo_advisory)
        pvr_submitter = pvr_advisory.author
        repo_owner = pvr_advisory.repository.owner
        pvr_advisory.remove_collaborator(pvr_submitter)

        updated_title = pvr_advisory.title + " (updated)"
        pvr_advisory.update(title: updated_title)

        repos = {}
        repos[pvr_advisory.repository.id.to_s] = pvr_advisory.repository
        summary = NotificationSummary.fetch_and_update!(pvr_advisory.repository, pvr_advisory, pvr_advisory)

        hash = serialize_hash_method(:rollup_summary_hash, summary.to_summary_hash, repos: repos,
          current_user: repo_owner).with_indifferent_access

        assert_equal updated_title, hash[:subject][:title]
        refute_equal pvr_advisory.frozen_title, hash[:subject][:title]
      end
    end
  end
end
