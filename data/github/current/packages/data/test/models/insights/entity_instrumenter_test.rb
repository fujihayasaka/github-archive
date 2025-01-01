# typed: false
# frozen_string_literal: true

require "test_helper"

class Insights::EntityInstrumenterTest < GitHub::TestCase
  include HydroTestHelpers

  class FakeIssue < ApplicationRecord::Domain::IssuesPullRequests
    self.table_name = "issues"
    include Insights::EntityInstrumenter
    attr_accessor :repository

    def insights_enterprise_entity
      @repository.try(:owner)
    end

    def insights_entity_shard_id
      @repository.id
    end

    def insights_entity_attributes
      {
        id: self.id,
        repository_id: self.repository_id,
        title: self.title
      }
    end

    def immutable_record?
      false
    end
  end

  class FakeIssueLabel < ApplicationRecord::Domain::IssuesPullRequests
    self.table_name = "issues_labels"
    include Insights::EntityInstrumenter
    attr_accessor :issue
    attr_accessor :label

    def insights_enterprise_entity
      @issue.try(:repository).try(:owner)
    end

    def insights_entity_shard_id
      @issue.try(:repository).try(:owner).try(:id)
    end

    def insights_entity_attributes
      {
        id: self.id_before_type_cast,
        issue_id: self.issue_id_before_type_cast,
        label_id: self.label_id_before_type_cast
      }
    end

    def immutable_record?
      true
    end
  end

  class FakeIssueWithoutInsightsEnterpriseEntityId < ApplicationRecord::Domain::IssuesPullRequests
    self.table_name = "issues"
    include Insights::EntityInstrumenter
    attr_accessor :repository

    def insights_entity_shard_id
      @repository.id
    end

    def insights_entity_attributes
      {
        id: self.id,
        repository_id: self.repository_id,
        title: self.title
      }
    end

    def immutable_record?
      false
    end
  end

  class FakeIssueWithoutInsightsEntityShardId < ApplicationRecord::Domain::IssuesPullRequests
    self.table_name = "issues"
    include Insights::EntityInstrumenter
    attr_accessor :repository

    def insights_enterprise_entity
      @repository.try(:owner)
    end

    def insights_entity_attributes
      {
        id: self.id,
        repository_id: self.repository_id,
        title: self.title
      }
    end

    def immutable_record?
      false
    end
  end

  class FakeIssueWithoutInsightsEntityAttributes < ApplicationRecord::Domain::IssuesPullRequests
    self.table_name = "issues"
    include Insights::EntityInstrumenter
    attr_accessor :repository

    def insights_enterprise_entity
      @repository.try(:owner)
    end

    def insights_entity_shard_id
      @repository.id
    end

    def immutable_record?
      false
    end
  end

  class EntityWithNoOrgId < ApplicationRecord::Domain::IssuesPullRequests
    self.table_name = "issues"
    include Insights::EntityInstrumenter
    attr_accessor :repository
    def insights_enterprise_entity
      nil
    end

    def insights_entity_shard_id
      @repository.id
    end

    def insights_entity_attributes
      {
        id: self.id,
        repository_id: self.repository_id,
        title: self.title
      }
    end

    def immutable_record?
      false
    end
  end

  fixtures do
    @owner        = create :user, login: "owner", plan: "large"
    @repository   = create :private_repository, owner: @owner
    @label_fixture = create :label, repository_id: @repository.id
    @issue_fixture = create :issue, repository_id: @repository.id
  end

  setup do
    @issue = FakeIssue.new(repository_id: @repository.id)
    @issue.repository = @repository
  end

  context "Including entity does not contain orgId" do
    test "Ensure hydro message not published for entity when orgId is nil" do
      @test_entity = EntityWithNoOrgId.create(repository_id: @repository.id)
      @test_entity.repository = @repository
      @test_entity.save
      assert GlobalInstrumenter.expects(:instrument).with("insights.entity_destroyed", has_entry(message: has_entry(entity: "entity_with_no_org_id"))).never
      @test_entity.instrument_insights_entity_event("insights.entity_destroyed", Time.now.utc)
    end
  end

  context "Including class implements #insights_enterprise_entity_id" do
    test "it enqueues an Insights::IncrementalIngestionJob in the after_create_commit hook" do
      Insights::Access.stubs(:enabled?).with(@owner).returns(true)
      @issue.save
      expected_args = ->(job_args) do
        job_args[0] == "insights.entity_created" &&
        job_args[1] == "Insights::EntityInstrumenterTest::FakeIssue" &&
        job_args[2] == Issue.last.id &&
        job_args[3].is_a?(Time)
      end
      assert_enqueued_with(job: Insights::IncrementalIngestionJob, args: expected_args)
    end

    test "it enqueues an Insights::IncrementalIngestionJob in the after_update_commit hook" do
      Insights::Access.stubs(:enabled?).with(@owner).returns(true)
      @issue.save
      @issue.update(title: "Some Title")
      expected_args = ->(job_args) do
        job_args[0] == "insights.entity_updated" &&
        job_args[1] == "Insights::EntityInstrumenterTest::FakeIssue" &&
        job_args[2] == @issue.id &&
        job_args[3].is_a?(Time)
      end
      assert_enqueued_with(job: Insights::IncrementalIngestionJob, args: expected_args)
    end

    test "it enqueues an Insights::IncrementalIngestion::DestroyedJob in the after_destroy_commit hook" do
      Insights::Access.stubs(:enabled?).with(@owner).returns(true)
      @issue.save
      expected_args = ->(job_args) do
        job_args[0] == @issue.insights_entity_name &&
        job_args[1] == @issue.insights_entity_destroyed_job_payload(job_args[2]) &&
        job_args[2].is_a?(Time)
      end
      assert_enqueued_with(job: Insights::IncrementalIngestion::EntityDestroyedJob, args: expected_args) do
        @issue.destroy
      end
    end

    test "#insights_entity_activity_payload" do
      @issue.save
      source_time = Time.now.utc
      payload = {
        message: {
          entity: "issue",
          data: {
            id: @issue.id,
            repository_id: @issue.repository_id,
            title: @issue.title,
            source_time: source_time.strftime("%Y-%m-%d %H:%M:%S %z")
          },
          insights_enterprise_entity_id: @issue.repository.owner.id,
          insights_entity_shard_id: @repository.id
        },
        partition_key: "issue:#{@issue.id}"
      }
      assert_equal @issue.insights_entity_activity_payload(source_time), payload
    end

    test "#insights_entity_enterprise_id" do
      assert_equal @issue.insights_enterprise_entity_id, @owner.id
    end

    test "#insights_entity_shard_id" do
      assert_equal @issue.insights_entity_shard_id, @repository.id
    end

    context "#instrument_insights_entity_event" do
      test "instruments the create topic" do
        assert GlobalInstrumenter.expects(:instrument).with("insights.entity_created", has_entry(message: has_entry(entity: "issue")))
        @issue.instrument_insights_entity_event("insights.entity_created", Time.now.utc)
      end

      test "instruments the update topic" do
        assert GlobalInstrumenter.expects(:instrument).with("insights.entity_updated", has_entry(message: has_entry(entity: "issue")))
        @issue.instrument_insights_entity_event("insights.entity_updated", Time.now.utc)
      end

      test "instruments the delete topic" do
        assert GlobalInstrumenter.expects(:instrument).with("insights.entity_destroyed", has_entry(message: has_entry(entity: "issue")))
        @issue.instrument_insights_entity_event("insights.entity_destroyed", Time.now.utc)
      end
    end

    context "#insights_formatted_timestamp" do
      test "return before_type_cast value for field when formatted_timestamp_publish FF is off" do
        @issue.update(created_at: Time.current)
        GitHub.flipper[:insights_formatted_timestamp_publish].disable(@owner)

        assert_equal @issue.created_at_before_type_cast, @issue.insights_formatted_timestamp(:created_at)
      end

      test "return formatted value for field when formatted_timestamp_publish FF is on" do
        @issue.update(created_at: Time.new(2023, 1, 8))
        GitHub.flipper[:insights_formatted_timestamp_publish].enable(@owner)

        assert_equal "2023-01-08T08:00:00Z", @issue.insights_formatted_timestamp(:created_at)
      end
    end

  end

  context "including class does not implement #insights_enterprise_entity" do
    test "after_commit hooks raise a NotImplemented error" do
      assert_raises NotImplementedError do
        FakeIssueWithoutInsightsEnterpriseEntityId.create(repository_id: @repository.id)
      end
    end
  end

  context "including class does not implement #insights_entity_shard_id" do
    test "after_commit hooks raise a NotImplemented error" do
      assert_raises NotImplementedError do
        @fake_issue = FakeIssueWithoutInsightsEntityShardId.create(repository_id: @repository.id)
        @fake_issue.insights_entity_activity_payload(Time.now.utc)
      end
    end
  end

  context "including class does not implement #insights_entity_attributes" do
    test "after_commit hooks raise a NotImplemented error" do
      assert_raises NotImplementedError do
        @fake_issue = FakeIssueWithoutInsightsEntityAttributes.create(repository_id: @repository.id)
        @fake_issue.insights_entity_activity_payload(Time.now.utc)
      end
    end
  end

  context "Event publishing" do
    test "it publishes create events to Hydro" do
      source_time = Time.now.utc
      expected_payload = @issue.insights_entity_activity_payload(source_time)
      expected_payload[:message][:data] = Hydro::EntitySerializer.insights_data(@issue.insights_entity_activity_payload(source_time)[:message][:data])

      @issue.instrument_insights_entity_event("insights.entity_created", source_time)

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        assert_hydro_published_partial(
          expected_payload[:message],
          schema: "github.insights.v0.EntityCreated",
          partition_key: expected_payload[:partition_key])
      end
    end

    test "it publishes update events to Hydro" do
      source_time = Time.now.utc
      expected_payload = @issue.insights_entity_activity_payload((source_time))
      expected_payload[:message][:data] = Hydro::EntitySerializer.insights_data(@issue.insights_entity_activity_payload(source_time)[:message][:data])

      @issue.instrument_insights_entity_event("insights.entity_updated", source_time)

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        assert_hydro_published_partial(
          expected_payload[:message],
          schema: "github.insights.v0.EntityUpdated",
          partition_key: expected_payload[:partition_key])
      end
    end

    test "it can be used to publish delete events to Hydro" do
      source_time = Time.now.utc
      expected_payload = @issue.insights_entity_activity_payload(source_time)
      expected_payload[:message][:data] = Hydro::EntitySerializer.insights_data(@issue.insights_entity_activity_payload(source_time)[:message][:data])

      payload = @issue.insights_entity_destroyed_job_payload(source_time)
      GlobalInstrumenter.instrument("insights.entity_destroyed", payload)

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        assert_hydro_published_partial(
          expected_payload[:message],
          schema: "github.insights.v0.EntityDeleted",
          partition_key: expected_payload[:partition_key])
      end
    end
  end
end
