# typed: strict
# frozen_string_literal: true

require "test_helper"

class ReportDependencyTest < GitHub::TestCase
  context "can_report?", skip_enterprise: true do
    test "user can report public repos but cannot report their own repos" do
      repo = create(:public_repository)

      assert repo.can_report?(create(:user))
      refute repo.can_report?(repo.owner)
    end

    test "nil viewer can report" do
      repo = create(:public_repository)
      assert repo.can_report?(nil)
    end

    test "member of orgs can report org repos" do
      org = create(:organization)
      member = create(:user)
      repo = create(:public_repository, owner: org)
      org.add_member(member)

      assert repo.can_report?(member)
    end

    test "Cannot report private repositories" do
      repo = create(:private_repository)

      refute repo.can_report?(create(:user))
      refute repo.can_report?(repo.owner)
    end

    test "Cannot report inactive repositories" do
      repo = create(:public_repository, active: false)

      refute repo.can_report?(create(:user))
      refute repo.can_report?(repo.owner)
    end

    test "Cannot report if the repo's access is disabled" do
      repo = create(:repository)
      repo.access.disable("size", repo.owner, dmca_takedown: "http://foobar.com")

      refute repo.can_report?(create(:user))
    end
  end
end
