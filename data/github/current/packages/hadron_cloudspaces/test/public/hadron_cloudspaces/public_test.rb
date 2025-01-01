# typed: true
# frozen_string_literal: true

require "test_helper"

class HadronCloudspaces::PublicTest < GitHub::TestCase
  include CodespacesPlanFixtures
  include GitHub::ComponentTestHelpers

  class FakeCreateResult
    include FactoryBot::Syntax::Methods
    include CloudEnvironments::ICreateResult
    extend T::Sig

    sig { params(owner: T.nilable(User), repository_id: T.nilable(Integer), pull_request: T.nilable(PullRequest), provisioned: T::Boolean).void }
    def initialize(
      owner:,
      repository_id:,
      pull_request:,
      provisioned: true
    )
      @owner = owner
      @repository_id = repository_id
      @pull_request = pull_request
      @provisioned = provisioned
      if @provisioned
        @github_token = "abc"
        @github_token_valid_after = Time.now.to_f
      end
    end

    sig { override.returns(T.nilable(CloudEnvironments::ICloudEnvironment)) }
    def cloud_environment
      return nil unless @owner && @repository_id && @pull_request
      return @cloud_environment if defined?(@cloud_environment)

      @cloud_environment = create(:cloud_environment, owner: @owner, repository_id: @repository_id, pull_request: @pull_request)
      @cloud_environment.tap { |ce| ce.update(guid: SecureRandom.uuid, state: :provisioned) }
    end

    sig { override.returns(T.nilable(Codespaces::Environment)) }
    def env
      return nil unless @cloud_environment
      ::Codespaces::Environment.from_json({ "id" => @cloud_environment.guid, "connection" => {} })
    end

    sig { override.returns(T.nilable(String)) }
    attr_reader :github_token

    sig { override.returns(T.nilable(Float)) }
    attr_reader :github_token_valid_after

    sig { override.returns(T::Boolean) }
    def provisioned?; @provisioned; end
  end

  setup do
    make_trusted_oauth_apps_owner
    @integration = create(:codespaces_integration)
    Codespaces::Secret.stubs(:assemble).returns([])

    @owner = create(:user)
    create(:feature_with_flipper, :opt_out, slug: "copilot_hadron_editor")
    GitHub.flipper[:copilot_hadron_editor].enable
    @owner.enable_feature_preview(:copilot_hadron_editor)
    @repository = create(:repository, owner: @owner, from_example: :simple)
    @master_head = @repository.heads.find_or_build(@repository.default_branch)
    head_ref = @repository.heads.create("patch-1", @master_head.target, @owner)
    head_ref.append_commit({ message: "some changes", committer: @owner }, @owner) do |files|
      files.add("file001", "foo")
    end
    @pull_request = create(:pull_request, repository: @repository, base_repository: @repository, head_repository: @repository,  user: @owner, base_ref: @repository.default_branch, head_ref: "patch-1")
    @operation = create(:codespaces_async_operation, operation: :create_codespace)
  end

  context "find_or_create" do
    test "creates a hadron cloudspace" do
      pull_request = new_pr!

      create_result = FakeCreateResult.new(owner: @owner, repository_id: @repository.id, pull_request:)
      CloudEnvironments::Public.stubs(create: create_result)

      result = HadronCloudspaces::Public.find_or_create(
        owner: @owner,
        repository_id: @repository.id,
        pull_request_number: pull_request.number,
        location: "EastUs",
        operation: @operation
      )

      assert result.hadron_cloudspace
      assert result.hadron_cloudspace&.cloud_environment
      refute result.found?
    end

    test "finds a hadron cloudspace on the PR" do
      pull_request = new_pr!
      create(:task_cloud_environment, owner: @owner, repository: @repository, pull_request: pull_request)
      result = HadronCloudspaces::Public.find_or_create(
        owner: @owner,
        repository_id: @repository.id,
        pull_request_number: pull_request.number,
        location: "EastUs",
        operation: @operation
      )

      assert result.hadron_cloudspace
      assert result.hadron_cloudspace&.cloud_environment
      assert result.found?
    end
  end

  def new_pr!(branch_name = SecureRandom.hex)
    ref = @repository.heads.find_or_build("master")
    head_ref = @repository.heads.create(branch_name, ref.target, @owner)
    head_ref.append_commit({ message: "some changes", committer: @owner }, @owner) do |files|
      files.add("file001", "foo")
    end

    create(:pull_request, repository: @repository, base_repository: @repository, head_repository: @repository,  user: @owner, base_ref: "master", head_ref: branch_name)
  end
end
