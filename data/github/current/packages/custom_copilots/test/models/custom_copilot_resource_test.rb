# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomCopilotResourceTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper # for cap_authorizing_filter, cap_unauthorizing_filter

  fixtures do
    @user = create(:user)

    @custom_copilot = create(:custom_copilot, owner: @user, current_user: @user, cap_filter: cap_authorizing_filter)

    @second_user = create(:user)

    @accessible_repo = create(:repository, owner: @user, name: "somerepo")
    @accessible_custom_copilot = create(:custom_copilot, owner: @user, current_user: @user, cap_filter: cap_authorizing_filter)

    @inaccessible_org = create(:copilot_feature_enabled_enterprise_organization, login: "copilot-inaccessible-org")
    @inaccessible_org.add_member(@second_user)
    @inaccessible_custom_copilot = create(:custom_copilot, owner: @inaccessible_org, current_user: @user, cap_filter: cap_authorizing_filter)
    @inaccessible_repo = create(:private_repository, owner: @inaccessible_org, name: "inaccessible repo")

    @repo = create(:repository, owner: @user, name: "filerepo")
    @file_path = "docs/README.md"
    @file_contents = "# Test File\nContent here"
    ref = @repo.heads.read(@repo.default_branch)
    ref.append_commit({ message: "Add test file", author: @repo.owner }, @repo.owner) do |files|
      files.add(@file_path, @file_contents)
    end
    ref.freeze
  end

  setup do
    @custom_copilot.current_user = @user
    @custom_copilot.cap_filter = cap_authorizing_filter
    @accessible_custom_copilot.current_user = @user
    @accessible_custom_copilot.cap_filter = cap_authorizing_filter
    @inaccessible_custom_copilot.current_user = @user
    @inaccessible_custom_copilot.cap_filter = cap_authorizing_filter
  end

  test "belongs to a custom_copilot" do
    repo = create(:repository, owner: @user)

    resource = CustomCopilotResource.new(
      custom_copilot: @custom_copilot,
      resource_type: :github_file,
      metadata: {
        repository_id: @repo.id,
        file_path: @file_path,
      }
    )
    assert resource.valid?
    resource.save!
    assert_equal @custom_copilot.id, resource.custom_copilot&.id
  end

  context "free_text resource types" do
    test "validates that name and text are present" do
      resource = CustomCopilotResource.new(
        custom_copilot: @custom_copilot,
        resource_type: :free_text,
        metadata: {
          text: "",
          name: ""
        }
      )

      refute resource.valid?
      assert_equal ["can't be blank"], resource.errors[:text]
      assert_equal ["can't be blank"], resource.errors[:name]
    end

    test "validates that text is not too long" do
      resource = CustomCopilotResource.new(
        custom_copilot: @custom_copilot,
        resource_type: :free_text,
        metadata: {
          text: "a" * 20_001
        }
      )

      refute resource.valid?
      assert_equal ["is too long"], resource.errors[:text]
    end

    test "creates a free_text resource" do
      resource = CustomCopilotResource.new(
        custom_copilot: @custom_copilot,
        resource_type: :free_text,
        metadata: {
          text: "Some free text",
          name: "My file"
        }
      )

      assert resource.valid?
      resource.save!
      assert_equal "Some free text", resource.text
      assert_empty resource.errors[:text]
    end

    test "parsed_metadata returns correct metadata instance" do
      resource = CustomCopilotResource.new(
        custom_copilot: @custom_copilot,
        resource_type: :free_text,
        metadata: {
          text: "Some free text"
        }
      )

      metadata = resource.parsed_metadata
      assert_instance_of CustomCopilotResource::FreeTextMetadata, metadata
      assert_equal "Some free text", metadata.text
    end
  end

  context "#to_copilot_config_twirp" do
    test "converts github file resource to twirp format, using the default branch as the ref for the file" do
      repository = create(:repository, owner: @user, name: "test-repo")
      ref = repository.heads.read(repository.default_branch)
      file_path = "docs/README.md"
      file_contents = "# Test File\nContent here"

      ref.append_commit({ message: "Add test file", author: repository.owner }, repository.owner) do |files|
        files.add(file_path, file_contents)
      end
      ref.freeze

      resource = create(:custom_copilot_resource,
        resource_type: :github_file,
        custom_copilot: @custom_copilot,
        metadata: {
          repository_id: repository.id,
          file_path: file_path,
        }
      )

      twirp_resource = resource.to_copilot_config_twirp

      assert_equal resource.id, twirp_resource.id
      assert_equal :"RESOURCE_TYPE_GITHUB_FILE", twirp_resource.resource_type

      file_metadata = twirp_resource.git_hub_file_metadata
      assert_equal repository.owner_display_login, file_metadata.owner
      assert_equal repository.name, file_metadata.name
      assert_equal repository.default_branch, file_metadata.ref
      assert_equal file_path, file_metadata.path
      assert_equal file_contents, file_metadata.contents
      assert_equal repository.default_oid, file_metadata.sha
    end

    test "converts free text resource to twirp format" do
      resource = create(:custom_copilot_resource,
        resource_type: :free_text,
        custom_copilot: @custom_copilot,
        metadata: {
          name: "My file",
          text: "File text"
        }
      )

      twirp_resource = resource.to_copilot_config_twirp

      assert_equal resource.id, twirp_resource.id
      assert_equal :"RESOURCE_TYPE_FREE_TEXT", twirp_resource.resource_type

      metadata = twirp_resource.free_text_metadata
      assert_equal "File text", metadata.contents
    end
  end

  context "#size" do
    test "returns correct size for free text resource" do
      text = "Some free text"
      resource = CustomCopilotResource.new(
        resource_type: :free_text,
        custom_copilot: @custom_copilot,
        metadata: {
          text: text
        }
      )

      assert_equal text.bytesize, resource.size
    end

    test "returns correct size for github file resource" do
      resource = CustomCopilotResource.new(
        resource_type: :github_file,
        custom_copilot: @custom_copilot,
        metadata: {
          repository_id: @repo.id,
          file_path: @file_path,
        }
      )

      assert_equal @file_contents.bytesize, resource.size
    end

    test "logs error for repo not found" do
      deleted_repo = create(:repository, :soft_deleted, owner: @user, name: "deletedrepo")
      resource = CustomCopilotResource.new(
        resource_type: :github_file,
        custom_copilot: @custom_copilot,
        metadata: {
          repository_id: deleted_repo.id,
        }
      )

      GitHub.logger.expects(:error).with(
        "custom_copilot.custom_copilot_resource.size: repository not found",
        {
          "gh.copilot.custom_copilot.id": @custom_copilot.id,
          "gh.copilot.custom_copilot.owner_id": @user.id,
          "gh.copilot.custom_copilot.resource.id": nil,
          "gh.copilot.custom_copilot.resource.metadata": { "repository_id" => deleted_repo.id },
        }
      )
      assert_equal 0, resource.size
    end

    test "logs error for repo resource" do
      resource = CustomCopilotResource.new(
        resource_type: :unknown,
        custom_copilot: @custom_copilot,
        metadata: {
          some_key: 123,
        }
      )

      GitHub.logger.expects(:error).with(
        "custom_copilot.custom_copilot_resource.size: resource type not supported",
        {
          "gh.copilot.custom_copilot.id": @custom_copilot.id,
          "gh.copilot.custom_copilot.owner_id": @user.id,
          "gh.copilot.custom_copilot.resource.id": nil,
          "gh.copilot.custom_copilot.resource.metadata": { "some_key" => 123 },
        }
      )
      assert_equal 0, resource.size
    end
  end
end
