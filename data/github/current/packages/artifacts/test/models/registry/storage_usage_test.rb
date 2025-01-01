# typed: true
# frozen_string_literal: true

require "test_helper"

class RegistryStorageUsageTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repository = create(:private_repository, owner: @user)

    @storage_usage = Registry::StorageUsage.new(owner: @user, repository: @repository)
  end

  context "#billing_actions_usage" do
    test "returns 0 when there are no ArtifactEvents" do
      billing_result = @storage_usage.billing_actions_usage

      assert_equal 0, billing_result
    end

    test "returns 0 when there are only Packages events" do
      create(:shared_storage_artifact_event, :add_event, :gpr_source, :private_visibility,
        repository: @repository, size_in_bytes: 400.megabytes)

      billing_result = @storage_usage.billing_actions_usage

      assert_equal 0, billing_result
    end

    test "it returns a correct value when there are ArtifactEvents" do
      create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
        repository: @repository, size_in_bytes: 400.megabytes)
      create(:shared_storage_artifact_event, :remove_event, :actions_source, :private_visibility,
        repository: @repository, size_in_bytes: 100.megabytes)

      billing_result = @storage_usage.billing_actions_usage

      assert_equal 300.megabytes, billing_result
    end
  end

  context "#billing_combined_usage" do
    test "returns 0 when there isn't aggregated or pending usage" do
      billing_result = @storage_usage.billing_combined_usage

      assert_equal 0, billing_result
    end

    test "returns the sum of the last aggregated and un-aggregated events" do
      create(:shared_storage_current_usage, :private_visibility,
        repository: @repository, aggregate_size_in_bytes: 450.megabytes,
        owner: @user, effective_at: Time.now)

      create(:shared_storage_artifact_event, :remove_event, :actions_source, :private_visibility,
        repository: @repository, size_in_bytes: 50.megabytes, aggregation_id: nil)

      billing_result = @storage_usage.billing_combined_usage

      assert_equal 400.megabytes, billing_result
    end
  end

  context "#billing_aggregated_usage" do
    test "returns 0 when a SharedStorage::CurrentUsage aggregate does not exist" do
      billing_result = @storage_usage.billing_aggregated_usage

      assert_equal 0, billing_result
    end

    test "returns the last aggregated value for the owner/repository" do
      create(:shared_storage_current_usage, :private_visibility,
        repository: @repository, aggregate_size_in_bytes: 450.megabytes,
        owner: @user, effective_at: Time.now)

      billing_result = @storage_usage.billing_aggregated_usage

      assert_equal 450.megabytes, billing_result
    end
  end

  context "#billing_pending_usage" do
    test "returns 0 when there are no ArtifactEvents" do
      billing_result = @storage_usage.billing_pending_usage

      assert_equal 0, billing_result
    end

    test "returns 0 when there are only aggregated events" do
      create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
        repository: @repository, size_in_bytes: 400.megabytes, aggregation_id: 42)

      billing_result = @storage_usage.billing_pending_usage

      assert_equal 0, billing_result
    end

    test "returns a correct value when there are un-aggregated events for actions and packages" do
      create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
        repository: @repository, size_in_bytes: 400.megabytes, aggregation_id: nil)
      create(:shared_storage_artifact_event, :remove_event, :gpr_source, :private_visibility,
        repository: @repository, size_in_bytes: 100.megabytes, aggregation_id: nil)

      billing_result = @storage_usage.billing_pending_usage

      assert_equal 300.megabytes, billing_result
    end
  end

  context "#billing_packages_usage" do
    test "returns 0 when there are no ArtifactEvents" do
      billing_result = @storage_usage.billing_packages_usage

      assert_equal 0, billing_result
    end

    test "returns 0 when there are only Actions events" do
      create(:shared_storage_artifact_event, :add_event, :actions_source, :private_visibility,
        repository: @repository, size_in_bytes: 400.megabytes)

      billing_result = @storage_usage.billing_packages_usage

      assert_equal 0, billing_result
    end

    test "it returns a correct value when there are ArtifactEvents" do
      create(:shared_storage_artifact_event, :add_event, :gpr_source, :private_visibility,
        repository: @repository, size_in_bytes: 400.megabytes)
      create(:shared_storage_artifact_event, :remove_event, :gpr_source, :private_visibility,
        repository: @repository, size_in_bytes: 100.megabytes)

      billing_result = @storage_usage.billing_packages_usage

      assert_equal 300.megabytes, billing_result
    end
  end

  context "#packages_usage" do
    test "returns 0 when there are no packages" do

      packages_usage = @storage_usage.packages_usage

      assert_equal 0, packages_usage
    end

    test "returns a correct value when there are packages with files" do
      create(:registry_package,
        repository: @repository,
        package_type: :docker,
        package_versions: [
          build(:registry_package_version, files: [
            build(:registry_package_file, package_version: @package_version, size: 300.megabytes),
            build(:registry_package_file, package_version: @package_version, size: 100.megabytes),
          ])
        ]
      )

      packages_usage = @storage_usage.packages_usage

      assert_equal 400.megabytes, packages_usage
    end
  end

  context "#packages_non_docker_usage" do
    test "returns 0 when there are no packages" do

      packages_usage = @storage_usage.packages_non_docker_usage

      assert_equal 0, packages_usage
    end

    test "returns 0 when there are only Docker packages" do
      create(:registry_package,
        repository: @repository,
        package_type: :docker,
        package_versions: [
          build(:registry_package_version, files: [build(:registry_package_file, package_version: @package_version, size: 300.megabytes)])
        ]
      )

      packages_usage = @storage_usage.packages_non_docker_usage

      assert_equal 0, packages_usage
    end

    test "returns a correct value when there are non-Docker packages with files" do
      create(:registry_package,
        repository: @repository,
        package_type: :rubygems,
        package_versions: [
          build(:registry_package_version, files: [build(:registry_package_file, package_version: @package_version, size: 100.megabytes)])
        ]
      )

      create(:registry_package,
        repository: @repository,
        package_type: :npm,
        package_versions: [
          build(:registry_package_version, files: [build(:registry_package_file, package_version: @package_version, size: 300.megabytes)])
        ]
      )

      packages_usage = @storage_usage.packages_non_docker_usage

      assert_equal 400.megabytes, packages_usage
    end
  end
end
