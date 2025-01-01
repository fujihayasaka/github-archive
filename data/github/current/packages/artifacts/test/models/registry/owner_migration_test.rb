# typed: false
# frozen_string_literal: true

require "test_helper"

class OwnerMigrationTest < GitHub::TestCase
  include GitHub::RegistryPackageHelper
  include HydroTestHelpers
  include CdnTestHelper
  include Registry::PackageDownloadStatsService

  fixtures do
    @user1 = create :user, login: "ownerMigrationUser1", password: GitHub.default_password
    @user2 = create :user, login: "ownerMigrationUser2", password: GitHub.default_password
    @user3 = create :user, login: "ownerMigrationUser3", password: GitHub.default_password
    @user2_state = Registry::OwnerMigration.create(owner_id: @user2.id, package_type: :docker, state: :inProgress)
    @user3_state = Registry::OwnerMigration.create(owner_id: @user3.id, package_type: :docker, state: :inProgress)
  end

  context ".basic" do
    test "create and get owner migration state" do
      state_created = Registry::OwnerMigration.create(owner_id: @user1.id, package_type: :docker, state: :retriableError)
      state_requested = Registry::OwnerMigration.find_by(owner_id: @user1.id, package_type: :docker)
      assert_equal state_created.id, state_requested.id
      assert_equal state_created.state, state_requested.state
    end

    test "update owner migration state" do
      state_request = :error
      state_owner_updated = Registry::OwnerMigration.find_by(owner_id: @user2.id, package_type: :docker)
      state_owner_updated.update(state: state_request)
      assert_equal Registry::OwnerMigration.states[state_request], Registry::OwnerMigration.states[state_owner_updated.state]
    end

    test "delete owner migration state" do
      user3_om = Registry::OwnerMigration.find_by(owner_id: @user3.id, package_type: :docker)
      refute_nil user3_om
      Registry::OwnerMigration.delete(user3_om.id)
      user3_om = Registry::OwnerMigration.find_by(owner_id: @user3.id, package_type: :docker)
      refute_nil !user3_om
    end

  end

end
