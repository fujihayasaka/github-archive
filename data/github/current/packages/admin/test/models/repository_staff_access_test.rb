# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryStaffAccessTest < GitHub::TestCase
  include UnlockedRepositoryCheckTestHelper

  fixtures do
    @repo = create(:repository, :minimal)
    @priv_repo = create(:private_repository, :minimal)
    @staffer  = create(:staff_admin_user, stafftools_roles: ["can-unlock-repos-with-owners-permission"])
    @user     = create(:user, login: "user")
    @nonstaff = create(:user, login: "non-staffer")
  end

  setup do
    clear_memoized_unlocked_repository_check
  end

  test "#request_staff_access creates a StaffAccessRequest for this repo" do
    assert_empty @repo.staff_access_requests
    request = @repo.request_staff_access(@staffer, "Investigating bugs")

    assert_equal request, @repo.staff_access_requests.last
  end

  test "is adminable by staff with an active unlock" do
    refute @repo.adminable_by?(@staffer)

    request = @repo.request_staff_access(@staffer, "because")
    request.accept @repo.owner
    @staffer.unlock_repository(@repo)
    clear_memoized_unlocked_repository_check

    assert @repo.adminable_by?(@staffer)
  end

  test "repository protections is adminable by staff with an active unlock" do
    refute @priv_repo.adminable_by?(@staffer)

    request = @priv_repo.request_staff_access(@staffer, "because")
    request.accept @priv_repo.owner
    @staffer.unlock_repository(@priv_repo)
    clear_memoized_unlocked_repository_check

    assert @priv_repo.private?
    assert @priv_repo.adminable_by?(@staffer)
    assert @priv_repo.async_can_edit_repo_protections?(@staffer).sync
  end
end
