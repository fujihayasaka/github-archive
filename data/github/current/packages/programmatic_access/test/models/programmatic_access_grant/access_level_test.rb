# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"

class ProgrammaticAccessGrant::AccessLevelTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures

  MissingRepoAttrs = Struct.new(:permissions)
  RepoMock = Struct.new(:id)

  fixtures do
    @access_level = described_class.from_hash(
      permissions: { "metadata" => :read },
      repository_ids: [42],
      repository_selection: "subset"
    )
  end

  def described_class
    ::ProgrammaticAccessGrant::AccessLevel
  end

  def custom_attribute_error
    ::ProgrammaticAccessGrant::AccessLevel::InvalidAttributeError
  end

  context "#from_grantable" do
    test "raises if grantable is nil" do
      assert_raises(custom_attribute_error) { described_class.from_grantable(nil) }
    end

    test "raises if grantable is missing attributes" do
      obj_missing_repo_attrs = MissingRepoAttrs.new(permissions: []).freeze
      assert_raises(custom_attribute_error) { described_class.from_grantable(obj_missing_repo_attrs) }
    end

    test "creates an access level from an user grant" do
      grant = create(:user_programmatic_access, :grants).grant
      access_level = described_class.from_grantable(grant)

      assert_instance_of described_class, access_level
    end

    test "creates an access level from an org grant" do
      grant = create(:user_programmatic_access, :org_grants).grant
      access_level = described_class.from_grantable(grant)

      assert_instance_of described_class, access_level
    end
  end

  context "#from_hash" do
    test "raises if hash is nil" do
      assert_raises(custom_attribute_error) { described_class.from_hash(nil) }
    end

    test "raises if hash lacks required keys" do
      assert_raises(custom_attribute_error) { described_class.from_hash({ permissions: {}, repository_ids: [] }) }
    end

    test "raises if hash has invalid repository selection" do
      assert_raises(custom_attribute_error) do
        described_class.from_hash({ permissions: {}, repository_ids: [], repository_selection: "some" })
      end
    end

    test "creates an access level from a hash" do
      attrs = {
        permissions: { "metadata" => :read },
        repository_ids: [42, 73],
        repository_selection: :subset
      }

      assert_instance_of described_class, described_class.from_hash(attrs)
    end

    test "extracts repository ids if repositories is given" do
      repo_double = RepoMock.new(id: 42)
      attrs = {
        permissions: { "metadata" => :read },
        repositories: [repo_double],
        repository_selection: :subset
      }

      assert_instance_of described_class, described_class.from_hash(attrs)
      assert_equal [42], described_class.from_hash(attrs).repository_ids
    end
  end

  context "greater_than" do
    test "raises when comparing against nil" do
      assert_raises(custom_attribute_error) { @access_level.greater_than?(nil) }
    end

    test "is false when access level has the same attributes than the other" do
      refute @access_level.greater_than?(@access_level)
    end

    test "compares repository selection" do
      new_level = described_class.from_hash(
        permissions: @access_level.permissions,
        repository_ids: @access_level.repository_ids,
        repository_selection: :all # higher repository selection
      )

      assert new_level > @access_level
      refute @access_level.greater_than?(new_level)
    end

    test "repository id replacements make new access level greater" do
      new_level = described_class.from_hash(
        permissions: @access_level.permissions,
        repository_ids: [73],
        repository_selection: @access_level.repository_selection
      )

      assert new_level > @access_level
      assert @access_level > new_level # is also true as all replacements have different access
    end

    test "added repository ids make access level greater" do
      new_level = described_class.from_hash(
        permissions: @access_level.permissions,
        repository_ids: [42, 73],
        repository_selection: @access_level.repository_selection
      )

      assert new_level > @access_level
    end

    test "removed repository ids make access level lower" do
      new_level = described_class.from_hash(
        permissions: @access_level.permissions,
        repository_ids: [],
        repository_selection: @access_level.repository_selection
      )

      refute new_level > @access_level
    end

    test "added permission make access level greater" do
      new_level = described_class.from_hash(
        permissions: @access_level.permissions.merge("plan" => :read),
        repository_ids: @access_level.repository_ids,
        repository_selection: @access_level.repository_selection
      )

      assert new_level > @access_level
      refute @access_level > new_level
    end

    test "removed permission make access level lower" do
      new_level = described_class.from_hash(
        permissions: {},
        repository_ids: @access_level.repository_ids,
        repository_selection: @access_level.repository_selection
      )

      refute new_level > @access_level
    end

    test "upgraded permission make access level greater" do
      new_level = described_class.from_hash(
        permissions: { "metadata" => :write }, # upgraded permission from read to write
        repository_ids: @access_level.repository_ids,
        repository_selection: @access_level.repository_selection
      )

      assert new_level > @access_level
      refute @access_level > new_level
    end
  end
end
