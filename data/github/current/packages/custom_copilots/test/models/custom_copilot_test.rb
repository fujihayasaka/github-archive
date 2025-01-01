# typed: true
# frozen_string_literal: true

require "test_helper"

class CustomCopilotTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers
  include ConditionalAccess::FilterTestHelper

  context "uuid" do
    test "is generated before validation" do
      user = create(:user)
      custom_copilot = CustomCopilot.new(
        name: "test",
        owner: user,
        description: "test",
        icon_url: "test",
        current_user: user,
        cap_filter: cap_authorizing_filter)
      assert_nil custom_copilot.uuid
      assert custom_copilot.valid?
      assert custom_copilot.uuid.present?
      assert_equal 36, custom_copilot.uuid.length
    end
  end

  test "for_uuid finds a record by its uuid, or nil if it can't be found" do
    custom_copilot = create(:custom_copilot, cap_filter: cap_authorizing_filter)
    assert custom_copilot.valid?
    assert custom_copilot.uuid

    assert_equal custom_copilot, CustomCopilot.for_uuid(custom_copilot.uuid)

    assert_nil CustomCopilot.for_uuid("non-existent-uuid")
  end

  test "belongs to user" do
    user = create(:user)

    custom_copilot = CustomCopilot.new(
      name: "test",
      owner: user,
      description: "test",
      icon_url: "test",
      current_user: user,
      cap_filter: cap_authorizing_filter)
    assert custom_copilot.valid?
    custom_copilot.save!

    custom_copilot.reload
    assert custom_copilot.id != nil
    assert custom_copilot.owner.is_a?(User)
    assert_equal custom_copilot.slug, "test"
    assert_equal custom_copilot.slug_with_owner, "#{user.display_login}/test"
  end

  test "belongs to org" do
    org = create(:organization)
    user = create(:user)

    custom_copilot = CustomCopilot.new(
      name: "test",
      owner: org,
      description: "test",
      icon_url: "test",
      current_user: user,
      cap_filter: cap_authorizing_filter)
    assert custom_copilot.valid?
    custom_copilot.save!

    custom_copilot.reload
    assert custom_copilot.id != nil
    assert custom_copilot.owner.is_a?(Organization)
    assert_equal custom_copilot.slug, "test"
    assert_equal custom_copilot.slug_with_owner, "#{org.display_login}/test"
  end

  test "has resources" do
    cap_stub = cap_authorizing_filter
    user = create(:user)

    custom_copilot = CustomCopilot.new(
      name: "test",
      owner: user,
      description: "test",
      icon_url: "test",
      current_user: user,
      cap_filter: cap_stub)
    custom_copilot.save!

    repo = create(:repository, owner: user)

    resource = CustomCopilotResource.new(
      custom_copilot: custom_copilot,
      resource_type: :github_file,
      metadata: {
        repository_id: repo.id,
        file_path: "README.md",
      }
    )
    resource.save!

    custom_copilot.reload
    assert_equal 1, custom_copilot.resources.count
  end

  test "deletes resources when the copilot is deleted" do
    cap_stub = cap_authorizing_filter
    user = create(:user)
    custom_copilot = create(:custom_copilot, current_user: user, cap_filter: cap_stub)
    resource = CustomCopilotResource.new(
      custom_copilot: custom_copilot,
      resource_type: :free_text,
      metadata: { name: "test name", text: "test text" }
    )
    assert resource.valid?
    resource.save!

    other_copilot = create(:custom_copilot, current_user: user, cap_filter: cap_stub)
    other_resource = CustomCopilotResource.new(
      custom_copilot: other_copilot,
      resource_type: :free_text,
      metadata: { name: "other name", text: "other text" }
    )
    assert other_resource.valid?
    other_resource.save!
    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = custom_copilot
      config.expect_destroyed = [resource]
      config.expect_not_destroyed = [other_resource]
    end
  end

  test "validates owner" do
    user = create(:user)

    custom_copilot = CustomCopilot.new(
      name: "test",
      owner: nil,
      description: "test",
      icon_url: "test",
      current_user: user,
      cap_filter: cap_authorizing_filter)

    refute custom_copilot.valid?
    assert_raises ActiveRecord::RecordInvalid do
      custom_copilot.save!
    end
  end

  test "validates max description length" do
    user = create(:user)

    custom_copilot = CustomCopilot.new(
      name: "test",
      owner: user,
      description: "test" * 1000,
      icon_url: "test",
      current_user: user,
      cap_filter: cap_authorizing_filter)

    refute custom_copilot.valid?
    assert_raises ActiveRecord::RecordInvalid do
      custom_copilot.save!
    end
  end

  test "validates max general instructions length" do
    user = create(:user)

    custom_copilot = CustomCopilot.new(
      name: "test",
      owner: user,
      general_instructions: "hi" * 2000,
      icon_url: "test",
      current_user: user,
      cap_filter: cap_authorizing_filter)

    refute custom_copilot.valid?
    assert_equal custom_copilot.errors.full_messages[0], "General instructions is too long (maximum is 2000 characters)"
    assert_raises ActiveRecord::RecordInvalid do
      custom_copilot.save!
    end
  end

  context "#free_text_resources_react_payload" do
    test "includes free text resources" do
      user = create(:user)
      custom_copilot = create(:custom_copilot, owner: user, current_user: user, cap_filter: cap_authorizing_filter)
      resource = create(:custom_copilot_resource, custom_copilot: custom_copilot, resource_type: :free_text, metadata: { text: "foo", name: "My file" })

      payload = custom_copilot.free_text_resources_react_payload

      assert_equal([{
        id: resource.id.to_s,
        databaseId: resource.id,
        text: "foo",
        markedForDestroy: false,
        type: "free_text",
        name: "My file"
      }], payload)
    end
  end

  context "authorized_repositories" do
    test "returns resources that are visible to the user and authorized by CAP" do
      cap_stub = cap_authorizing_filter
      user = create(:user)
      repo = create(:private_repository, owner: user)
      custom_copilot = create(:custom_copilot, owner: user, current_user: user, cap_filter: cap_stub)
      resource = create(:custom_copilot_resource, custom_copilot: custom_copilot, resource_type: :github_file, metadata: { repository_id: repo.id, file_path: "README.md" })

      payload = custom_copilot.authorized_repositories([resource], viewer: user, cap_filter: cap_stub)

      assert_equal 1, payload.count
      assert_equal([repo], payload)
    end

    test "fails to create resources that are unauthorized by the CAP filter to the user" do
      cap_stub = cap_unauthorizing_filter
      user = create(:user)
      repo = create(:private_repository, owner: user)
      custom_copilot = create(:custom_copilot, owner: user, current_user: user, cap_filter: cap_stub)
      resource = build(:custom_copilot_resource, custom_copilot: custom_copilot, resource_type: :github_file, metadata: { repository_id: repo.id, file_path: "README.md" })

      refute resource.valid?
      assert_equal ["not found"], resource.errors[:repository]
    end

    test "fails to create resources that are unreadable by the user" do
      cap_stub = cap_authorizing_filter
      user = create(:user)
      rando = create(:user)
      repo = create(:private_repository, owner: rando)
      custom_copilot = create(:custom_copilot, owner: user, current_user: user, cap_filter: cap_stub)
      resource = build(:custom_copilot_resource, custom_copilot: custom_copilot, resource_type: :github_file, metadata: { repository_id: repo.id, file_path: "README.md" })

      refute resource.valid?
      assert_equal ["not found"], resource.errors[:repository]
    end
  end

  context "#github_file_resources_react_payload" do
    test "returns resources that are visible to the user and authorized by CAP" do
      cap_stub = cap_authorizing_filter
      user = create(:user)
      repo = create(:private_repository, owner: user)
      custom_copilot = create(:custom_copilot, owner: user, current_user: user, cap_filter: cap_stub)
      resource = create(:custom_copilot_resource,
        custom_copilot: custom_copilot,
        resource_type: :github_file,
        metadata: {
          repository_id: repo.id,
          file_path: "README.md",
        }
      )

      payload = custom_copilot.github_file_resources_react_payload(viewer: user, cap_filter: cap_stub)

      assert_equal 1, payload.count
      assert_same_hash({
        id: resource.id.to_s,
        databaseId: resource.id,
        repositoryId: repo.id,
        nwo: repo.name_with_display_owner,
        filePath: "README.md",
        markedForDestroy: false,
        type: "github_file",
      }, payload.first)
    end

    test "does not return resources that are not github file resources" do
      cap_stub = cap_authorizing_filter
      user = create(:user)
      repo = create(:private_repository, owner: user)
      custom_copilot = create(:custom_copilot, owner: user, current_user: user, cap_filter: cap_stub)
      resource = create(:custom_copilot_resource,
        custom_copilot: custom_copilot,
        resource_type: :free_text,
        metadata: {
          name: "Test name",
          text: "Test text"
        }
      )

      payload = custom_copilot.github_file_resources_react_payload(viewer: user, cap_filter: cap_stub)

      assert_empty payload
    end

    test "fails to create repositories that are unauthorized by the CAP filter to the user" do
      cap_stub = cap_unauthorizing_filter
      user = create(:user)
      repo = create(:private_repository, owner: user)
      custom_copilot = create(:custom_copilot, owner: user, current_user: user, cap_filter: cap_stub)
      resource = build(:custom_copilot_resource,
        custom_copilot: custom_copilot,
        resource_type: :github_file,
        metadata: {
          repository_id: repo.id,
          file_path: "README.md",
        }
      )

      refute resource.valid?
      assert_equal ["not found"], resource.errors[:repository]
    end

    test "removes repositories that are unreadable by the user" do
      cap_stub = cap_authorizing_filter
      user = create(:user)
      rando = create(:user)
      repo = create(:private_repository, owner: rando)
      custom_copilot = create(:custom_copilot, owner: user, current_user: user, cap_filter: cap_stub)
      resource = build(:custom_copilot_resource,
        custom_copilot: custom_copilot,
        resource_type: :github_file,
        metadata: {
          repository_id: repo.id,
          file_path: "README.md",
        }
      )

      refute resource.valid?
      assert_equal ["not found"], resource.errors[:repository]
    end
  end

  test "validates slug uniqueness" do
    user = create(:user)

    custom_copilot = CustomCopilot.new(
      name: "test",
      owner: user,
      description: "test",
      icon_url: "test",
      current_user: user,
      cap_filter: cap_authorizing_filter)
    custom_copilot.save!

    custom_copilot2 = CustomCopilot.new(
      name: "test",
      owner: user,
      description: "test",
      icon_url: "test",
      current_user: user,
      cap_filter: cap_authorizing_filter)

    refute custom_copilot2.valid?
    error = assert_raises ActiveRecord::RecordInvalid do
      custom_copilot2.save!
    end
    assert_includes error.message, "Slug has already been taken"
  end

  test "validates slug uniqueness with different owner" do
    cap_stub = cap_authorizing_filter
    user = create(:user)
    user2 = create(:user)

    custom_copilot = CustomCopilot.new(
      name: "test",
      owner: user,
      description: "test",
      icon_url: "test",
      current_user: user,
      cap_filter: cap_stub)
    custom_copilot.save!

    custom_copilot2 = CustomCopilot.new(
      name: "test",
      owner: user2,
      description: "test",
      icon_url: "test",
      current_user: user2,
      cap_filter: cap_stub)

    assert custom_copilot2.valid?
  end

  test "validates its resources" do
    cap_stub = cap_authorizing_filter
    user = create(:user)

    custom_copilot = CustomCopilot.new(
      name: "test",
      owner: user,
      description: "test",
      icon_url: "test",
      current_user: user,
      cap_filter: cap_stub)
    custom_copilot.save!

    repo = create(:repository)
    resource = CustomCopilotResource.new(
      custom_copilot: custom_copilot,
      resource_type: :github_file,
      metadata: {
        repository_id: nil,
        file_path: ""
      }
    )

    refute resource.valid?
    assert resource.errors[:repository_id].present?
    assert resource.errors[:file_path].present?
  end

  test "validates name uniqueness" do
    user = create(:user)

    custom_copilot = CustomCopilot.new(
      name: "test",
      owner: user,
      description: "test",
      icon_url: "test",
      current_user: user,
      cap_filter: cap_authorizing_filter)
    custom_copilot.save!

    custom_copilot2 = CustomCopilot.new(
      name: "test",
      owner: user,
      description: "test",
      icon_url: "test",
      current_user: user,
      cap_filter: cap_authorizing_filter)

    refute custom_copilot2.valid?
    error = assert_raises ActiveRecord::RecordInvalid do
      custom_copilot2.save!
    end
    assert_includes error.message, "Name has already been taken"
  end

  context "validate_total_content_size" do
    test "should validate when size is under limit" do
      user = create(:user)
      custom_copilot = CustomCopilot.new(
        name: "test",
        owner: user,
        current_user: user,
        cap_filter: cap_authorizing_filter)
      custom_copilot.save!

      resource = CustomCopilotResource.create!(
        custom_copilot: custom_copilot,
        resource_type: :free_text,
        metadata: {
          name: "test",
          text: "Not a lot of text"
        }
      )

      custom_copilot.reload

      assert_equal 1, custom_copilot.resources.count
      assert custom_copilot.valid?
    end

    test "should not validate when size is over limit" do
      user = create(:user)
      custom_copilot = CustomCopilot.new(
        name: "test",
        owner: user,
        general_instructions: "a" * 1000,
        current_user: user,
        cap_filter: cap_authorizing_filter)
      custom_copilot.save!

      10.times do
        resource = CustomCopilotResource.create!(
          custom_copilot: custom_copilot,
          resource_type: :free_text,
          metadata: {
            name: "test",
            text: "b" * (CustomCopilot::MAX_CONTENT_SIZE / 10)
          }
        )
      end

      custom_copilot.reload

      assert_equal 10, custom_copilot.resources.count
      refute custom_copilot.valid?, "Custom copilot should not be valid when exceeding size limit"
      assert_includes custom_copilot.errors.full_messages, "The size of the space exceeds the current limit. Please remove a resource and try again."
    end

    test "should not count resources not authorized by CAP filter" do
      user = create(:user)
      repo = create(:repository, owner: user, name: "file-repo")
      file_path = "exact_limit.md"
      add_file_to_repo(repo, file_path, "a" * CustomCopilot::MAX_CONTENT_SIZE)

      custom_copilot = CustomCopilot.new(
        name: "test",
        owner: user,
        general_instructions: "b" * 1000,
        current_user: user,
        cap_filter: cap_authorizing_filter)
      custom_copilot.save!

      resource = CustomCopilotResource.create!(
        custom_copilot: custom_copilot,
        resource_type: :github_file,
        metadata: {
          repository_id: repo.id,
          file_path: file_path,
        }
      )

      custom_copilot.reload

      refute custom_copilot.valid? # user does see the oversized resources when authorized by CAP

      custom_copilot.cap_filter = cap_unauthorizing_filter

      assert custom_copilot.valid? # user does not see the oversized resources when blocked by CAP
    end

    test "should not count resources not visible to current user" do
      user = create(:user)
      another_user = create(:user)
      repo = create(:private_repository, owner: another_user, name: "file-repo")
      file_path = "exact_limit.md"
      add_file_to_repo(repo, file_path, "a" * CustomCopilot::MAX_CONTENT_SIZE)

      custom_copilot = CustomCopilot.new(
        name: "test",
        owner: user,
        general_instructions: "b" * 1000,
        current_user: another_user,
        cap_filter: cap_authorizing_filter)
      custom_copilot.save!

      resource = CustomCopilotResource.create!(
        custom_copilot: custom_copilot,
        resource_type: :github_file,
        metadata: {
          repository_id: repo.id,
          file_path: file_path,
        }
      )

      custom_copilot.reload

      refute custom_copilot.valid? # another_user does see the oversized resources

      custom_copilot.current_user = user

      assert custom_copilot.valid? # user does not see the oversized resources
    end

    test "should not count resources pending deletion" do
      user = create(:user)
      repo = create(:repository, owner: user, name: "file-repo")
      file_path = "exact_limit.md"
      add_file_to_repo(repo, file_path, "a" * CustomCopilot::MAX_CONTENT_SIZE)

      custom_copilot = CustomCopilot.new(
        name: "test",
        owner: user,
        current_user: user,
        general_instructions: "b" * 1000, # push it over the limit
        cap_filter: cap_authorizing_filter)
      custom_copilot.save!

      resource = CustomCopilotResource.create!(
        custom_copilot: custom_copilot,
        resource_type: :github_file,
        metadata: {
          repository_id: repo.id,
          file_path: file_path,
        }
      )

      custom_copilot.reload

      # Should not be valid at this point
      refute custom_copilot.valid?, "Custom copilot should not be valid when exceeding size limit"

      custom_copilot.resources[0].mark_for_destruction

      # Should be valid now that large resource is pending deletion
      assert custom_copilot.valid?
    end

    test "should gracefully handle previous resources that have been deleted" do
      user = create(:user)
      repo = create(:repository, owner: user, name: "file-repo")
      custom_copilot = CustomCopilot.new(
        name: "test",
        owner: user,
        current_user: user,
        cap_filter: cap_authorizing_filter,
        general_instructions: "Test")
      custom_copilot.save!

      resource = CustomCopilotResource.create!(
        custom_copilot: custom_copilot,
        resource_type: :github_file,
        metadata: {
          repository_id: repo.id,
          file_path: "no/longer/exists",
        }
      )

      custom_copilot.reload

      assert custom_copilot.valid?
    end

    test "returns protected organizations in the current space when resources are unauthorized by the CAP filter" do
      cap_stub = cap_authorizing_filter
      user = create(:user)
      org = create(:organization)
      org2 = create(:organization)
      custom_copilot = CustomCopilot.new(
        name: "test",
        owner: org,
        current_user: user,
        cap_filter: cap_stub)
      custom_copilot.save!

      # github file resources
      repo = create(:repository, owner: org, name: "repo1")
      file_path = "exact_limit.md"
      add_file_to_repo(repo, file_path, "a" * CustomCopilot::MAX_CONTENT_SIZE)
      create(:custom_copilot_resource, custom_copilot: custom_copilot, resource_type: :github_file, metadata: { repository_id: repo.id, file_path: file_path })

      repo2 = create(:repository, owner: org2, name: "repo2")
      file_path_2 = "exact_limit_2.md"
      add_file_to_repo(repo2, file_path_2, "a" * CustomCopilot::MAX_CONTENT_SIZE)
      create(:custom_copilot_resource, custom_copilot: custom_copilot, resource_type: :github_file, metadata: { repository_id: repo2.id, file_path: file_path_2 })

      custom_copilot.reload
      assert_equal 2, custom_copilot.resources.count
      assert_equal 2, custom_copilot.protected_organizations(custom_copilot: custom_copilot, cap_filter: cap_unauthorizing_filter).count
    end
  end

  private

  def add_file_to_repo(repo, file_path, contents)
    ref = repo.heads.read(repo.default_branch)
    ref.append_commit({ message: "Add test file", author: repo.owner }, repo.owner) do |files|
      files.add(file_path, contents)
    end
    ref.freeze
  end
end
