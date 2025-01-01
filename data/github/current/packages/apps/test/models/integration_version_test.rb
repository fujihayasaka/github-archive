# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationVersionTest < GitHub::TestCase
  test "requires integration" do
    version = create(:integration_version)
    version.integration_id = nil

    refute_predicate version, :valid?
    assert_predicate version.errors[:integration_id], :any?
  end

  test "requires number" do
    version = build(:integration_version, number: nil)
    refute_predicate version, :valid?
    assert_predicate version.errors[:number], :any?
  end

  test "requires a note to be 240 characters or less" do
    note = "A" * 241
    version = build(:integration_version, note: note)

    refute_predicate version, :valid?
    assert_predicate version.errors[:note], :any?
  end

  test "sets the next number on create" do
    integration = create(:integration)

    version = create(:integration_version, integration: integration)
    assert_equal 2, version.number

    version = create(:integration_version, integration: integration)
    assert_equal 3, version.number
  end

  test "numbering is scoped to the integration" do
    version = create(:integration_version)
    assert_equal 2, version.number

    version = create(:integration_version)
    assert_equal 2, version.number
  end

  test "has the same default events as its integration" do
    integration    = create(:integration, :with_hook, default_permissions: { "metadata" => :read }, default_events: %w(label))
    latest_version = integration.latest_version

    assert_equal integration.default_events, latest_version.default_events
  end

  test "allows only up to 5 content references per integration version" do
    content_references = {
      "runkit.com": :domain,
      "sentry.io": :domain,
      "runpad.com": :domain,
      "datadog.com": :domain,
      "atlassian.net": :domain,
      "slack.com": :domain,
    }
    version = build(:integration_version, default_content_references: content_references)
    refute_predicate version, :valid?
    assert_equal "is too long (maximum is 5 characters)", version.errors[:content_references].first
  end

  test "does not allow content reference permission without at least one content reference" do
    content_references = {}
    version = build(:integration_version, default_content_references: content_references, default_permissions: { "content_references" => :write })
    refute_predicate version, :valid?
    assert_equal "at least one reference is required.", version.errors[:content_references].first
  end

  test "does not allow content reference without the content reference permission set" do
    content_references = {
      "runkit.com": :domain,
    }

    version = build(:integration_version, default_content_references: content_references)
    refute_predicate version, :valid?
    assert_equal "access to content_references is required.", version.errors[:default_permissions].first
  end

  test "does not allow previews permissions that are not enabled for the owner" do
    Permissions::ResourceRegistry.stubs(preview_subject_type_flags: { "preview_subject_type" => :permissions_resource_registry })
    disable_feature_flag(:permissions_resource_registry)
    Repository::Resources.stub_const(:SUBJECT_TYPES, %w(metadata preview_subject_type)) do
      integration    = build(:integration, :with_hook, default_permissions: { "metadata" => :read, "preview_subject_type" => :write }, default_events: %w(label))

      refute_predicate integration, :valid?
      assert_includes integration.errors.full_messages, "Default permissions preview_subject_type are not supported permissions"
    end
  end

  test "allows preview permissions that are enabled for the owners business" do
    Permissions::ResourceRegistry.stubs(preview_subject_type_flags: { "preview_subject_type" => :permissions_resource_registry })
    Repository::Resources.stub_const(:SUBJECT_TYPES, %w(metadata preview_subject_type)) do
      organization = create(:organization, :enterprise_linked)
      enable_feature_flag(:permissions_resource_registry, organization.business)

      integration    = build(:integration, :with_hook, default_permissions: { "metadata" => :read, "preview_subject_type" => :write }, default_events: %w(label), owner: organization)

      assert_predicate integration, :valid?
    end
  end

  test "allows preview permissions that are enabled for the owner" do
    Permissions::ResourceRegistry.stubs(preview_subject_type_flags: { "preview_subject_type" => :permissions_resource_registry })
    enable_feature_flag(:permissions_resource_registry)
    Repository::Resources.stub_const(:SUBJECT_TYPES, %w(metadata preview_subject_type)) do
      integration    = build(:integration, :with_hook, default_permissions: { "metadata" => :read, "preview_subject_type" => :write }, default_events: %w(label))

      assert_predicate integration, :valid?
    end
  end

  test "allows only up to 10 single files per integration version" do
    version = create(:integration_version, default_permissions: { "single_file" => :read }, single_file_paths: [".travis.yml"])
    (1..10).each do |index|
      version.single_files.build(path: "file-numba-#{index}.txt")
    end

    refute_predicate version, :valid?
    assert_equal "has too many files (maximum is 10)", version.errors[:single_files].first
  end

  context "#single_file_paths" do
    test "returns an empty array if there aren't any single file paths" do
      version = create(:integration_version)

      assert_empty version.single_file_paths
    end

    test "returns an array of strings when there are single file paths" do
      version = create(:integration_version, default_permissions: { "single_file" => :read }, single_file_paths: [".travis.yml", "not-travis.txt"])

      assert_same_elements %w(.travis.yml not-travis.txt), version.single_file_paths
    end
  end

  context "#permissions_of_type" do
    test "returns an empty array if there aren't any permissions" do
      version = create(:integration_version)

      assert_predicate version.default_permissions, :empty?
      assert_predicate version.permissions_of_type(Repository), :empty?
    end

    test "returns all of the permissions are apart of a certain resource group" do
      version = create(:integration_version, default_permissions: { "metadata" => :read, "issues" => :read })
      assert_equal({ "metadata" => :read, "issues" => :read }, version.permissions_of_type(Repository))
    end

    test "returns filtered permissions if they are part of different resource groups" do
      version = create(:integration_version, default_permissions: { "emails" => :read, "metadata" => :read, "issues" => :read })
      assert_equal({ "metadata" => :read, "issues" => :read }, version.permissions_of_type(Repository))
    end
  end

  context "#permissions_relevant_to" do
    context "installation_type :integration_installation (default)" do
      test "returns Business permissions only when the target is a Business" do
        target  = create(:business)
        version = create(:integration_version, default_permissions: { "metadata" => :read, "enterprise_administration" => :read, "members" => :read, "emails" => :read })

        assert_equal({ "enterprise_administration" => :read }, version.permissions_relevant_to(target))
      end

      test "returns Repository permissions when the target is a User" do
        target  = create(:user)
        version = create(:integration_version, default_permissions: { "metadata" => :read, "enterprise_administration" => :read, "members" => :read, "emails" => :read })

        assert_equal({ "metadata" => :read }, version.permissions_relevant_to(target))
      end

      test "returns Repository and Organization permissions when the target is an Organization" do
        target  = create(:organization)
        version = create(:integration_version, default_permissions: { "metadata" => :read, "enterprise_administration" => :read, "members" => :read, "emails" => :read })

        assert_equal({ "metadata" => :read, "members" => :read }, version.permissions_relevant_to(target))
      end
    end

    context "installation_type :oauth_authorization" do
      test "returns nothing if the target is a Business" do
        target  = create(:business)
        version = create(:integration_version, default_permissions: { "metadata" => :read, "enterprise_administration" => :read, "members" => :read, "emails" => :read })

        assert_empty version.permissions_relevant_to(target, installation_type: :oauth_authorization)
      end

      test "returns User permissions when the target is a User" do
        target  = create(:user)
        version = create(:integration_version, default_permissions: { "metadata" => :read, "enterprise_administration" => :read, "members" => :read, "emails" => :read })

        assert_equal({ "emails" => :read }, version.permissions_relevant_to(target, installation_type: :oauth_authorization))
      end

      test "returns nothing if the target is an Organization" do
        target  = create(:organization)
        version = create(:integration_version, default_permissions: { "metadata" => :read, "enterprise_administration" => :read, "members" => :read, "emails" => :read })

        assert_empty version.permissions_relevant_to(target, installation_type: :oauth_authorization)
      end
    end
  end

  context "#all_permissions_of_type?" do
    test "returns false if there aren't any permissions" do
      version = create(:integration_version)

      assert_predicate version.default_permissions, :empty?
      refute version.all_permissions_of_type?(Repository)
    end

    test "returns true if all of the permissions are apart of a certain resource group" do
      version = create(:integration_version, default_permissions: { "metadata" => :read, "issues" => :read })
      assert version.all_permissions_of_type?(Repository)
    end

    test "returns false if the permissions are part of different resource groups" do
      version = create(:integration_version, default_permissions: { "emails" => :read, "issues" => :read })
      refute version.all_permissions_of_type?(Repository)
    end
  end

  context "#default_permissions" do
    test "returns mandatory permissions for scoped installations if the parent installation has them" do
      disable_feature_flag(:cached_fgp_permissions)

      repo = create(:repository, :minimal)
      parent_installation = make_integration_installation(
        repository: repo,
        permissions: { "metadata" => :read, "issues" => :read },
      )

      version = IntegrationVersion.new(parent_installation: parent_installation)
      version.default_permissions = { "issues" => :read }
      assert_equal({ "metadata" => :read, "issues" => :read }, version.default_permissions)

      # remove metadata from the parent and assert it's not automatically granted on the scoped record
      Permission.where(
        actor_id: parent_installation.id,
        actor_type: parent_installation.class.name,
        subject_type: repo.resources.metadata.ability_type,
      ).destroy_all

      version = IntegrationVersion.new(parent_installation: parent_installation)
      version.default_permissions = { "issues" => :read }
      assert_equal({ "issues" => :read }, version.default_permissions)
    end

    test "applies mandatory permissions for regular installations" do
      version = IntegrationVersion.new(default_permissions: { "issues" => :read })
      assert_equal({ "issues" => :read, "metadata" => :read }, version.default_permissions)
    end
  end

  context "#async_default_permissions" do
    test "returns the default_permissions as a Promise" do
      version = create(:integration_version, default_permissions: { "metadata" => :read }, default_events: ["public"])

      assert_kind_of Promise, version.async_default_permissions
      assert_equal({ "metadata" => :read }, version.async_default_permissions.sync)
    end
  end

  context "#async_default_events" do
    test "returns the default_events as a promise" do
      version = create(:integration_version, default_permissions: { "metadata" => :read }, default_events: ["public"])

      assert_kind_of Promise, version.async_default_events
      assert_same_elements ["public"], version.async_default_events.sync
    end
  end
end
