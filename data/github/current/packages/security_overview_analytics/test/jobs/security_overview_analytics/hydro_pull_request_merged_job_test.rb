# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroPullRequestMergedJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers
    include DogstatsTestHelpers

    # This allow me to prepare sample refs during fixture instead of setup
    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures

    fixtures do
      @queue = HydroPullRequestMergedJob.queue_name
      @schema = "github.v1.PullRequestMerge"

      @user = create(:user)
      @org = create(:organization, admin: @user)
      @repo = create(:repository, owner: @org, admin: @user, from_example: :simple)

      @master_head = @repo.heads.find_or_build("master")
      head_ref = @repo.heads.create("topic", @master_head.target, @user)
      head_ref.append_commit({ message: "some changes", committer: @user }, @user) do |files|
        files.add("file001", "foo")
      end

      @pull = create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        base_user: @user,
        base_ref: @repo.default_branch,
        head_repository: @repo,
        head_user: @user,
        head_ref: head_ref.name,
        user: @user,
      )

      on_multi_tenant_enterprise do
        @mt_user = create(:emu)
        @mt_business = @mt_user.enterprise_managed_business
        @mt_org = create :enterprise_linked_organization, :with_org_namespacing, business: @mt_business, admin: @mt_user
        @mt_repo = create(:private_repository, owner: @mt_org, admin: @mt_user, from_example: :simple)
        mt_repo_master_head = @mt_repo.heads.find_or_build("master")
        mt_repo_topic_head_ref = @mt_repo.heads.create("topic", mt_repo_master_head.target, @mt_user)
        mt_repo_topic_head_ref.append_commit({ message: "some changes", committer: @mt_user }, @mt_user) do |files|
          files.add("file001", "foo")
        end
        @mt_pull = create(:pull_request,
          repository: @mt_repo,
          base_repository: @mt_repo,
          base_user: @mt_user,
          base_ref: @mt_repo.default_branch,
          head_repository: @mt_repo,
          head_user: @mt_user,
          head_ref: mt_repo_topic_head_ref.name,
          user: @mt_user,
        )
      end
    end

    context "#perform" do
      test "enqueues ingestion job" do
        message = {
          pull_request: Hydro::EntitySerializer.pull_request(@pull),
          repository: Hydro::EntitySerializer.repository(@repo),
        }

        assert_enqueued_with(
          job: CodeScanningPullRequestAlertsIngestionJob,
          args: [pull_request_id: @pull.id, source_event: "github.v1.PullRequestMerge"]
        ) do
          assert_query_counts(0) do
            perform_hydro_message_job(message, schema: @schema, queue: @queue)
          end
        end

        assert_dogstats_increment 1, "security_overview_analytics.event.pull_request_merged.processed"
        refute_dogstats_increment "security_overview_analytics.event.pull_request_merged.skipped"
      end
    end

    context "on multi tenant enterprise" do
      test "sets the tenant context to the correct business" do
        on_multi_tenant_enterprise do
          message = {
            pull_request: Hydro::EntitySerializer.pull_request(@mt_pull),
            repository: Hydro::EntitySerializer.repository(@mt_repo),
          }

          ::Repositories::Public.expects(:resolve_tenant).with(id: @mt_repo.id).returns(@mt_business).once

          assert_enqueued_with(
            job: CodeScanningPullRequestAlertsIngestionJob,
            args: [pull_request_id: @mt_pull.id, source_event: "github.v1.PullRequestMerge"]
          ) do
            assert_query_counts(0) do
              perform_hydro_message_job(message, schema: @schema, queue: @queue)
            end
          end

          assert_dogstats_increment 1, "security_overview_analytics.event.pull_request_merged.processed"
          refute_dogstats_increment "security_overview_analytics.event.pull_request_merged.skipped"
        end
      end
    end
  end
end
