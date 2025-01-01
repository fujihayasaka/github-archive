# typed: true
# frozen_string_literal: true

require "test_helper"

class IntegrationInstallation::RepositoryAccessFilterTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo_one = create(:private_repository, :minimal, owner: @org)
    @repo_two = create(:private_repository, :minimal, owner: @org)

    @installation = make_integration_installation(repository: @repo_one, permissions: { "metadata" => :read })
  end

  test "returns a list of repos and the installation's grant status" do
    isv = mock
    isv.stubs(:installation).returns(@installation)

    orv = mock
    orv.stubs(:repositories).returns([@repo_one, @repo_two])

    raf = IntegrationInstallation::RepositoryAccessFilter.new(
      installation_show_view: isv,
      org_repo_index_view: orv,
    )

    expected = [
      [@repo_one, true],
      [@repo_two, false]
    ]
    assert_same_elements expected, raf.repositories_with_grant_status
  end
end
