# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryHasAppsThatWriteChecksTest < GitHub::TestCase
  fixtures do
    @github_app_with_permission = create(:integration, default_permissions: { "checks" => :write })
    @github_app_without_permission = create(:integration, default_permissions: { "checks" => :read })
    @repo = create(:repository, :minimal)
  end

  test "returns true if there are installations on the repository with write permission on 'checks'" do
    make_integration_installation(repository: @repo, integration: @github_app_with_permission)

    assert @repo.has_apps_that_write_checks?
  end

  test "returns false if there are no installations on the repository with write permission on 'checks'" do
    make_integration_installation(repository: @repo, integration: @github_app_without_permission)

    refute @repo.has_apps_that_write_checks?
  end

  test "returns false if there are no installations on the repository" do
    refute @repo.has_apps_that_write_checks?
  end
end
