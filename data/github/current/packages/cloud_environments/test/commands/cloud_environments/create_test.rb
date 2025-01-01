# typed: true
# frozen_string_literal: true

require "test_helper"

module CloudEnvironments
  class CreateTest < GitHub::TestCase
    include DogstatsTestHelpers
    include CodespacesPlanFixtures
    include GitHub::LoggerHelper

    class TestStatsTagger
      include IStatsTagger

      attr_accessor :tags

      def initialize(tags = {})
        @tags = tags
      end

      sig { override.returns(T::Array[String]) }
      def datadog_tags
        tags.map { |k, v| "#{k}:#{v}" }
      end

      sig { override.returns(T::Hash[Symbol, T.any(Integer, String, T::Boolean)]) }
      def all_tags
        tags
      end

      sig { override.returns(T::Hash[Symbol, T.any(Integer, String, T::Boolean)]) }
      def all_semconv_tags
        tags
      end
    end

    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @owner = create(:user)

      @repository = create(:repository, owner: @owner, from_example: :simple)
      @master_head = @repository.heads.find_or_build(@repository.default_branch)
      head_ref = @repository.heads.create("patch-1", @master_head.target, @owner)
      head_ref.append_commit({ message: "some changes", committer: @owner }, @owner) do |files|
        files.add("file001", "foo")
      end
      @pull_request = create(:pull_request, repository: @repository, base_repository: @repository, head_repository: @repository,  user: @owner, base_ref: @repository.default_branch, head_ref: "patch-1")
      @location = "EastUs"
      @operation = create(:codespaces_async_operation, operation: :create_codespace)
      @base_oid = Codespaces::GetTargetRef.call(repository: @repository, name_or_oid: @repository.default_branch).target_oid
    end

    setup do
      make_trusted_oauth_apps_owner
      @integration = create(:codespaces_integration)

      Codespaces::Secret.stubs(:assemble).returns([])
      @provisioner = Codespaces::ProvisionEnvironment
      @provisioner.stubs(call: Codespaces::Environment.new)
      CloudEnvironments::Create.any_instance.stubs(:provisioner).returns(@provisioner)
      @stats_tagger = TestStatsTagger.new
    end

    test "creates a cloud environment with provided attributes" do
      result = CloudEnvironments::Create.call(
        attributes: {
          owner: @owner,
          repository_id: @repository.id,
          location: @location,
          ref: @repository.default_branch,
          oid: @base_oid,
          sku_name: "standardLinux32gb",
        },
        provisioner: @provisioner,
        operation: @operation,
        stats_tagger: @stats_tagger,
      )
      assert result.cloud_environment
      assert_equal @owner, result.cloud_environment.owner
      assert_equal @repository, result.cloud_environment.repository
      assert_equal @location, result.cloud_environment.location
      assert_equal @repository.default_branch, result.cloud_environment.ref
      assert_equal @base_oid, result.cloud_environment.oid
      assert_equal "standardLinux32gb", result.cloud_environment.sku_name
    end

    context "token minting", skip_enterprise: true do
      test "returns github token" do
        result = CloudEnvironments::Create.call(
          attributes: {
            owner: @owner,
            repository_id: @repository.id,
            location: @location,
            ref: @repository.default_branch,
            oid: @base_oid,
            sku_name: "standardLinux32gb",
          },
          provisioner: @provisioner,
          operation: @operation,
          stats_tagger: @stats_tagger,
        )
        refute_nil result.github_token
      end
    end

    context "provisioning", skip_enterprise: true do
      test "schedules a provisioning job in case we hit a global request timeout" do
        assert_enqueued_with(job: CodespacesProvisionJob) do
          CloudEnvironments::Create.call(
            attributes: {
              owner: @owner,
              repository_id: @repository.id,
              location: @location,
              ref: @repository.default_branch,
              oid: @base_oid,
              sku_name: "standardLinux32gb",
            },
            provisioner: @provisioner,
            operation: @operation,
            stats_tagger: @stats_tagger,
          )
        end
      end

      test "attempts to provision the cloud environment" do
        @provisioner.expects(:call).once.returns(Codespaces::Environment.new)
        CloudEnvironments::Create.call(
          attributes: {
            owner: @owner,
            repository_id: @repository.id,
            location: @location,
            ref: @repository.default_branch,
            oid: @base_oid,
            sku_name: "standardLinux32gb",
          },
          provisioner: @provisioner,
          operation: @operation,
          stats_tagger: @stats_tagger,
        )
      end
    end

    context "logging", skip_enterprise: true do
      test "logs creation context" do
        expected_log_data = {
          "Body" => "codespace.created",
          "gh.catalog_service" => "github/codespaces",
          "gh.codespaces.billable_owner_login" => @owner.login,
          "gh.codespaces.owner_login" => @owner.login,
          "gh.repo.name_with_owner" => @repository.name_with_display_owner,
          "gh.codespaces.region" => @location,
        }

        assert_logged **expected_log_data do
          CloudEnvironments::Create.call(
            attributes: {
              owner: @owner,
              repository_id: @repository.id,
              location: @location,
              ref: @repository.default_branch,
              oid: @base_oid,
              sku_name: "standardLinux32gb",
            },
            provisioner: @provisioner,
            operation: @operation,
            stats_tagger: @stats_tagger,
          )
        end
      end
    end

    context "stats", skip_enterprise: true do
      test "emits appropriate metrics to datadog" do
        @stats_tagger.tags = { foo: "bar" }
        CloudEnvironments::Create.call(
          attributes: {
            owner: @owner,
            repository_id: @repository.id,
            location: @location,
            ref: @repository.default_branch,
            oid: @base_oid,
            sku_name: "standardLinux32gb",
          },
          provisioner: @provisioner,
          operation: @operation,
          stats_tagger: @stats_tagger,
        )
        assert_dogstats_increment(1, "codespace.created", tags: ["foo:bar"])
        assert_dogstats_distribution(1, "codespace.created.dist", tags: ["foo:bar"])
      end
    end
  end
end
