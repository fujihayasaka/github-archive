# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroRepositoryRenamedJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers

    fixtures do
      # Referencing the job class forces it to load
      # This is necessary for job to show up during queue name lookup
      @queue = HydroRepositoryRenamedJob.queue_name
      @schema = "github.v1.RepositoryRename"

      @org = create(:organization)
      @repo = create(:private_repository, owner: @org)
      @soa_repo = create(:security_overview_analytics_repository, repository: @repo)
    end

    setup do
      TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(@org.id).returns(true)
    end

    context "when repo lifecycle events are not being handled for the org" do
      test "it does nothing" do
        TenantValidationHelper.stubs(:should_handle_repository_lifecycle_events?).with(@org.id).returns(false)

        assert_no_changes(-> { @soa_repo.reload.name }) do
          message = make_message(repo: @repo, previous_name: @soa_repo.name, current_name: "bar")
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end
    end

    test "it updates name" do
      assert_changes(
        -> { @soa_repo.reload.name },
        from: @soa_repo.name,
        to: "bar"
      ) do
        message = make_message(repo: @repo, previous_name: @soa_repo.name, current_name: "bar")
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end
    end

    test "it updates event_time" do
      assert_changes(
        -> { @soa_repo.reload.event_time }
      ) do
        message = make_message(repo: @repo, previous_name: @soa_repo.name, current_name: "bar")
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end
    end

    test "it updates updated_at" do
      assert_changes(
        -> { @soa_repo.reload.updated_at }
      ) do
        message = make_message(repo: @repo, previous_name: @soa_repo.name, current_name: "bar")
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end
    end

    private

    sig do
      params(
        repo: ::Repository,
        previous_name: String,
        current_name: String
      ).returns(T::Hash[String, T.untyped])
    end
    def make_message(repo:, previous_name:, current_name:)
      T.cast(::Hydro::Schemas::Github::V1::RepositoryRename.new(
        repository: ::Hydro::Schemas::Github::V1::Entities::Repository.new(
          id: repo.id,
          owner_id: Google::Protobuf::UInt32Value.new(value: repo.owner_id)
        ),
        previous_name:,
        current_name:
      ), T.untyped).to_h
    end
  end
end
