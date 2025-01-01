# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryGroupMapTest < GitHub::TestCase
  fixtures do
    @biz = Business.first || create(:business)
    @org = create(:organization, business: @biz, plan: "business_plus")
    @repo = create(:public_repository, owner: @org)
    @group = RepositoryGroup.create!(owner: @org, group_path: "foo")
  end

  test "find_by" do
    RepositoryGroupMap.create!(repository_group: @group, repository: @repo)

    assert_equal @repo, RepositoryGroupMap.find_by(repository_group: @group)&.repository
    assert_equal @group, RepositoryGroupMap.find_by(repository: @repo)&.repository_group
    assert_equal @group, @repo.group
  end
end
