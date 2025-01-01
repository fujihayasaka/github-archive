# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroDeletePackagesRepositoryDeletedJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  setup do
    @queue = "hydro_delete_packages_repository_deleted"
    @schema = "github.repositories.v1.Deleted"
    @repo = create(:repository)
    @package = create(:registry_package, repository: @repo)
  end

  test "should delete packages" do
    message = { repository_id: @repo.id }

    not_deleted_versions = @repo.packages
      .map { |package| package.package_versions.not_deleted }
      .flatten

    refute_empty not_deleted_versions

    perform_hydro_message_job(message, schema: @schema, queue: @queue)

    not_deleted_versions = @repo.packages
      .map { |package| package.package_versions.not_deleted }
      .flatten

    assert_empty not_deleted_versions
  end
end
