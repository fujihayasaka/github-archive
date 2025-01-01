# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::SponsorshipDependenciesExportTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user)
    @viewer = @org_admin
    @org = create(:organization, :sponsorable, admin: @org_admin)
    @org_repo = create(:repository_sponsorable, :owner, sponsorable: @org).repository
  end

  if GitHub.sponsors_enabled?
    test "It generates a CSV with list of sponsorables and their associated dependencies" do
      sponsorable = create(:user, :sponsorable)
      dependency = create(:repository_sponsorable, :owner, sponsorable: sponsorable).repository
      fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
        data: { repositoryOwnerDependencies: { dependencies: [dependency.id] } },
      })
      DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
      export = Sponsors::SponsorshipsDependenciesExport.new(
        org: @org,
        viewer: @viewer,
      ).csv

      csv = T.unsafe(CSV.parse(export, headers: true))

      assert_equal sponsorable.login, csv[0]["maintainer_login"]
      assert_equal dependency.name, csv[0]["your_dependencies_they_maintain_or_own"]
      refute_nil csv[0]["recent_activity"]
    end
  end
end
