# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryGroupTest < GitHub::TestCase
  fixtures do
    @biz = Business.first || create(:business)
    @org = create(:organization, business: @biz, plan: "business_plus")
    # create org2 and some repos to test that we don't get them mixed up
    @org2 = create(:organization, business: @biz, plan: "business_plus")

    @repo1 = create(:public_repository, owner: @org, name: "repo1")
    decoy1 = create(:public_repository, owner: @org2, name: "foo/bar")
    @repo2 = create(:public_repository, owner: @org, name: "repo2", group_path: "")
    @repo3 = create(:public_repository, owner: @org, name: "repo3", group_path: "foo")
    decoy2 = create(:public_repository, owner: @org2, group_path: "")
    @repo4 = create(:public_repository, owner: @org, name: "repo4", group_path: "foo/bar")
    @repo5 = create(:public_repository, owner: @org, name: "repo5", group_path: "FOO")
    @repo6 = create(:public_repository, owner: @org, name: "repo6", group_path: "food")
    decoy3 = create(:public_repository, owner: @org2, group_path: "foo")
  end

  test "remove" do
    foobar = RepositoryGroup.find_by!(owner: @org, group_path: "foo/bar")
    foobar.remove
    assert_equal "foo", @repo3.reload.group_path
    assert_equal "foo", @repo4.reload.group_path
    assert_equal "foo", @repo5.reload.group_path
    assert_nil RepositoryGroup.find_by(owner: @org, group_path: "foo/bar")

    foo = RepositoryGroup.find_by!(owner: @org, group_path: "foo")
    foo.remove
    assert_equal "", @repo3.reload.group_path
    assert_equal "", @repo4.reload.group_path
    assert_equal "", @repo5.reload.group_path
    assert_nil RepositoryGroup.find_by(owner: @org, group_path: "foo")

    root = RepositoryGroup.find_by!(owner: @org, group_path: "")
    assert_raises(ArgumentError) { root.remove }
    assert_equal "", @repo3.reload.group_path
    assert_equal "", @repo4.reload.group_path
    assert_equal "", @repo5.reload.group_path
    assert RepositoryGroup.find_by(owner: @org, group_path: "")
  end

  test "rename" do
    foo = RepositoryGroup.find_by!(owner: @org, group_path: "foo")
    foobar = RepositoryGroup.find_by!(owner: @org, group_path: "foo/bar")
    foofoo = RepositoryGroup.find_or_create_group(owner: @org, group_path: "foo/foo")
    foofoofoo = RepositoryGroup.find_or_create_group(owner: @org, group_path: "foo/foo/foo")

    foo.rename("goo")
    assert_equal "goo", foo.reload.group_path
    assert_equal "goo/foo", foofoo.reload.group_path
    assert_equal "goo/foo/foo", foofoofoo.reload.group_path

    # detects existing group
    assert_raises(ArgumentError) { foofoo.rename("goo") }

    # detects existing food group and fixes casing
    foofoo.rename("FOOD/fooo")
    assert_equal "goo", foo.reload.group_path
    assert_equal "food/fooo", foofoo.reload.group_path
    assert_equal "food/fooo/foo", foofoofoo.reload.group_path

    # creates any missing parent groups
    foofoo.rename("a/B/c/d")
    assert_equal "goo", foo.reload.group_path
    assert_equal "a/B/c/d", foofoo.reload.group_path
    assert_equal "a/B/c/d/foo", foofoofoo.reload.group_path
    assert RepositoryGroup.find_by!(owner: @org, group_path: "a")
    assert RepositoryGroup.find_by!(owner: @org, group_path: "a/B")
    assert RepositoryGroup.find_by!(owner: @org, group_path: "a/B/c")
  end

  test "find_or_create_group" do
    # create the all node groups, using the casing provided
    group = RepositoryGroup.find_or_create_group(owner: @org2, group_path: "a1A")
    assert_equal "a1A", group.group_path
    group2 = RepositoryGroup.find_or_create_group(owner: @org2, group_path: "A1a")
    assert_equal group, group2

    group = RepositoryGroup.find_or_create_group(owner: @org2, group_path: "a1A/b2B/c3C")
    assert_equal "a1A/b2B/c3C", group.group_path
    group2 = RepositoryGroup.find_or_create_group(owner: @org2, group_path: "a1a/b2b/c3c")
    assert_equal group, group2

    group = RepositoryGroup.find_or_create_group(owner: @org2, group_path: "The/quick/BROWN/foX")
    assert_equal "The/quick/BROWN/foX", group.group_path
    assert_equal "The", RepositoryGroup.find_by!(owner: @org2, group_path: "The").group_path
    assert_equal "The/quick", RepositoryGroup.find_by!(owner: @org2, group_path: "the/QUICK").group_path
    assert_equal "The/quick/BROWN", RepositoryGroup.find_by!(owner: @org2, group_path: "the/QUIck/broWN").group_path
    assert_equal "The/quick/BROWN/foX", RepositoryGroup.find_by!(owner: @org2, group_path: "the/quick/brown/fox").group_path
  end

  test "validate group path" do
    assert_predicate RepositoryGroup.new(owner: @org, group_path: ""), :valid?
    assert_predicate RepositoryGroup.new(owner: @org, group_path: "Fo1.0-5_o"), :valid?
    assert_predicate RepositoryGroup.new(owner: @org, group_path: "FOO/bAr3"), :valid?
    assert_predicate RepositoryGroup.new(owner: @org, group_path: "a/B/C/d/1/2/3"), :valid?

    refute_predicate RepositoryGroup.new(owner: @org, group_path: "foo/"), :valid?
    refute_predicate RepositoryGroup.new(owner: @org, group_path: "/foo"), :valid?
    refute_predicate RepositoryGroup.new(owner: @org, group_path: "/foo/"), :valid?
    refute_predicate RepositoryGroup.new(owner: @org, group_path: "/foo/bar/"), :valid?
    refute_predicate RepositoryGroup.new(owner: @org, group_path: "foo$"), :valid?
    refute_predicate RepositoryGroup.new(owner: @org, group_path: "foo^"), :valid?
    refute_predicate RepositoryGroup.new(owner: @org, group_path: "a/b/c/d/e/f/g/h"), :valid?
  end

  test "move group" do
    group = @repo6.join_group("foo")
    assert_equal "foo", @repo6.group_path
    assert_equal @repo3.group, group

    @repo6.join_group("foo/bar/cat/dog")
    assert_equal "foo/bar/cat/dog", @repo6.group_path

    @repo6.join_group("food")
    assert_equal "food", @repo6.group_path
  end

  test "leave group means you join the root" do
    root_group = RepositoryGroup.find_by!(owner: @org, group_path: "")
    group = @repo6.group
    assert_equal 1, group.repositories.count

    @repo6.leave_group
    assert_equal root_group, @repo6.group
    assert group.reload
    assert_equal 0, group.repositories.count

    # should succeed at doing nothing
    @repo6.leave_group
    assert_equal root_group, @repo6.group
  end

  test "case insensitive" do
    group1 = RepositoryGroup.find_by!(owner: @org, group_path: "fOo")
    group2 = RepositoryGroup.find_by!(owner: @org, group_path: "fOO")

    expected = "foo" # because this was the casing when it was first created

    assert_equal expected, group1.group_path
    assert_equal expected, group2.group_path
    assert_equal expected, @repo3.group_path
    assert_equal expected, @repo5.group_path
  end

  test "save and load" do
    groups = RepositoryGroup.where(owner: @org)
    assert_equal 4, groups.count
    group_paths = groups.map(&:group_path)

    assert_same_elements ["", "foo", "food", "foo/bar"], group_paths
  end

  test "repository_group" do
    assert_nil RepositoryGroupMap.find_by(repository: @repo1)
    assert_equal "", RepositoryGroupMap.find_by!(repository: @repo2).repository_group&.group_path
    assert_equal "foo", RepositoryGroupMap.find_by!(repository: @repo3).repository_group&.group_path
    assert_equal "foo/bar", RepositoryGroupMap.find_by!(repository: @repo4).repository_group&.group_path
  end

  test "no group" do
    repos = RepositoryGroup.repositories_with_no_group(@org)
    assert_same_elements [@repo1], repos
    assert_same_elements [@repo1], repos.select { |r| r.group_path.nil? }

    repo7 = create(:public_repository, owner: @org)
    repos = RepositoryGroup.repositories_with_no_group(@org)
    assert_same_elements [@repo1, repo7], repos
    assert_same_elements [@repo1, repo7], repos.select { |r| r.group_path.nil? }
  end

  test "repositories" do
    repos = RepositoryGroup.find_by!(owner: @org, group_path: "").repositories
    assert_same_elements [@repo2], repos

    repos = RepositoryGroup.find_by!(owner: @org, group_path: "foo").repositories
    assert_same_elements [@repo3, @repo5], repos
    assert_same_elements [@repo3, @repo5], repos.select { |r| r.group_path == "foo" }

    repos = RepositoryGroup.find_by!(owner: @org, group_path: "foo/bar").repositories
    assert_same_elements [@repo4], repos
    assert_same_elements [@repo4], repos.select { |r| r.group_path == "foo/bar" }
  end

  test "repository summary with no groups" do
    RepositoryGroupMap.delete_all
    RepositoryGroup.delete_all
    summary = RepositoryGroup.repository_summary(@org)

    expected =
    {
      "" =>
      {
        group_id: nil,
        direct_count: 6,
        total_count: 6,
        repos: [
          { name: @repo1.name, id: @repo1.id },
          { name: @repo2.name, id: @repo2.id },
          { name: @repo3.name, id: @repo3.id },
          { name: @repo4.name, id: @repo4.id },
          { name: @repo5.name, id: @repo5.id },
          { name: @repo6.name, id: @repo6.id }
        ]
      },
    }
    assert_same_hash expected, summary
  end

  test "repository summary" do
    # move all repos out of the "foo" group to get coverage of empty groups
    foo_group = RepositoryGroup.find_by!(owner: @org, group_path: "foo")
    @repo3.join_group("foo/bar")
    @repo5.join_group("foo/bar")

    summary = RepositoryGroup.repository_summary(@org)

    expected =
    {
      "" =>
      {
        group_id: @repo2.group.id,
        direct_count: 2,
        total_count: 6,
        repos: [{ name: @repo1.name, id: @repo1.id }, { name: @repo2.name, id: @repo2.id }]
      },
      "foo" =>
      {
        group_id: foo_group.id,
        direct_count: 0,
        total_count: 3,
        repos: []
      },
      "foo/bar" =>
      {
        group_id: @repo4.group.id,
        direct_count: 3,
        total_count: 3,
        repos: [{ name: @repo3.name, id: @repo3.id }, { name: @repo4.name, id: @repo4.id }, { name: @repo5.name, id: @repo5.id }]
      },
      "food" =>
      {
        group_id: @repo6.group.id,
        direct_count: 1,
        total_count: 1,
        repos: [{ name: @repo6.name, id: @repo6.id }]
      }
    }
    assert_same_hash expected, summary
  end

  test "repositories_under" do
    repos = RepositoryGroup.find_by!(owner: @org, group_path: "").repositories_under
    assert_same_elements [@repo2, @repo3, @repo4, @repo5, @repo6], repos

    repos = RepositoryGroup.find_by!(owner: @org, group_path: "foo").repositories_under
    assert_same_elements [@repo3, @repo4, @repo5], repos

    repos = RepositoryGroup.find_by!(owner: @org, group_path: "foo/bar").repositories_under
    assert_same_elements [@repo4], repos
  end

  test "repository_batch" do
    ids, watermark = RepositoryGroup.find_by!(owner: @org, group_path: "").repository_batch(watermark: 0, batch_size: 100)
    assert_same_elements [@repo2.id, @repo3.id, @repo4.id, @repo5.id, @repo6.id], ids
    assert_equal @repo6.group_map.id, watermark

    ids, watermark = RepositoryGroup.find_by!(owner: @org, group_path: "foo").repository_batch(watermark: 0, batch_size: 100)
    assert_same_elements [@repo3.id, @repo4.id, @repo5.id], ids
    assert_equal @repo5.group_map.id, watermark

    ids, watermark = RepositoryGroup.find_by!(owner: @org, group_path: "foo/bar").repository_batch(watermark: 0, batch_size: 100)
    assert_same_elements [@repo4.id], ids
    assert_equal @repo4.group_map.id, watermark

    RepositoryGroup.find_or_create_group(owner: @org, group_path: "empty")
    ids, watermark = RepositoryGroup.find_by!(owner: @org, group_path: "empty").repository_batch(watermark: 0, batch_size: 100)
    assert_empty ids
    assert_equal 0, watermark
  end

  test "repository_batch batch_size" do
    ids, watermark = RepositoryGroup.find_by!(owner: @org, group_path: "").repository_batch(watermark: 0, batch_size: 2)
    assert_same_elements [@repo2.id, @repo3.id], ids
    assert_equal @repo3.group_map.id, watermark

    ids, watermark = RepositoryGroup.find_by!(owner: @org, group_path: "").repository_batch(watermark: watermark, batch_size: 2)
    assert_same_elements [@repo4.id, @repo5.id], ids
    assert_equal @repo5.group_map.id, watermark
  end

  test "repository_batch watermark" do
    # delete/recreate group_maps to test the batch watermark works when the group_map.ids are not in the same order as repo ids
    @repo4.group_map.delete
    @repo4.reload.join_group("foo/bar")
    @repo3.group_map.delete
    @repo3.reload.join_group("foo")

    # repos are ordered based on repository_group_map.id, so repo2 and repo5 should be first
    ids, watermark = RepositoryGroup.find_by!(owner: @org, group_path: "").repository_batch(watermark: 0, batch_size: 3)
    assert_same_elements [@repo2.id, @repo5.id, @repo6.id], ids
    assert_equal @repo6.group_map.id, watermark

    ids, watermark = RepositoryGroup.find_by!(owner: @org, group_path: "").repository_batch(watermark: watermark, batch_size: 3)
    assert_same_elements [@repo4.id, @repo3.id], ids
    assert_equal @repo3.group_map.id, watermark
  end

  test "in group" do
    refute @repo1.in_group?("")
    refute @repo1.in_group?("foo")
    refute @repo1.in_group?("foo/bar")

    assert @repo2.in_group?("")
    refute @repo2.in_group?("foo")
    refute @repo2.in_group?("food")
    refute @repo2.in_group?("foo/bar")

    assert @repo3.in_group?("")
    assert @repo3.in_group?("foo")
    refute @repo3.in_group?("food")
    refute @repo3.in_group?("foo/bar")

    assert @repo4.in_group?("")
    assert @repo4.in_group?("foo")
    assert @repo4.in_group?("foo/bar")
    refute @repo4.in_group?("food")

    assert @repo5.in_group?("")
    assert @repo5.in_group?("foo")
    refute @repo5.in_group?("food")
    refute @repo5.in_group?("foo/bar")

    assert @repo6.in_group?("")
    assert @repo6.in_group?("food")
    refute @repo6.in_group?("foo")
    refute @repo6.in_group?("foo/bar")
  end

  test "create and join group" do
    @repo1.join_group("new")
    assert_equal "new", @repo1.group_path
    assert @repo1.in_group?("new")
  end
end
