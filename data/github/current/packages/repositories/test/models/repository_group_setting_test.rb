# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryGroupSettingTest < GitHub::TestCase
  fixtures do
    @biz = Business.first || create(:business)
    @org = create(:organization, business: @biz, plan: "business_plus")
    @org2 = create(:organization, business: @biz, plan: "business_plus")

    @repo1 = create(:public_repository, owner: @org)
    @repo2 = create(:public_repository, owner: @org, group_path: "")
    @repo3 = create(:public_repository, owner: @org, group_path: "foo")
    @repo4 = create(:public_repository, owner: @org, group_path: "foo/bar")

    # create some decoy groups too
    RepositoryGroup.create!(owner: @org, group_path: "f")
    RepositoryGroup.create!(owner: @org, group_path: "food")
    RepositoryGroup.create!(owner: @org, group_path: "foo/bar/cat")
    RepositoryGroup.create!(owner: @org2, group_path: "")
    RepositoryGroup.create!(owner: @org2, group_path: "foo")

    PaintGroupSetting.add(@org, "", value = { colors: ["blue"] })
    PaintGroupSetting.add(@org, "foo", value = { colors: ["green"] })
    PaintGroupSetting.add(@org, "food", value = { colors: ["yellow"] })
    PaintGroupSetting.add(@org, "foo/bar", value = { colors: %w[blue purple] })

    SportsGroupSetting.add(@org, "f", value = { "ball": ["tennis"], "no_ball": ["chess"] })
    SportsGroupSetting.add(@org, "foo/bar", value = { "ball": ["football"], "no_ball": ["track"] })
    SportsGroupSetting.add(@org, "foo/bar/cat", value = { "ball": %w[baseball soccer], "no_ball": ["swimming"] })
  end

  test "add" do
    s1 = SportsGroupSetting.add(@org, "new", value = { "ball": ["tennis"], "no_ball": ["chess"] })
    s2 = SportsGroupSetting.add(@org, "new", value = { "ball": ["tennis"], "no_ball": ["chess"] })
    assert_equal s1, s2
    s3 = SportsGroupSetting.add(@org, "new", value = { "ball": ["pickleball"], "no_ball": ["diving"] })
    assert_equal s1.id, s3.id
    assert_same_elements ["pickleball"], s3.value["ball"]
    assert_same_elements ["diving"], s3.value["no_ball"]
  end

  test "for repository" do
    assert_nil PaintGroupSetting.for_repository(@repo1)
    if GitHub.flipper[:repos_groups].enabled?
      assert_same_elements ["blue"], PaintGroupSetting.for_repository(@repo2)&.composite["colors"]
      assert_same_elements %w[blue green], PaintGroupSetting.for_repository(@repo3)&.composite["colors"]
      assert_same_elements %w[blue green purple], PaintGroupSetting.for_repository(@repo4)&.composite["colors"]
    else
      assert_nil PaintGroupSetting.for_repository(@repo2)
      assert_nil PaintGroupSetting.for_repository(@repo3)
      assert_nil PaintGroupSetting.for_repository(@repo4)
    end
  end

  test "load_by_group" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "")
    sports = SportsGroupSetting.load_by_group(group)
    assert_nil sports

    group = RepositoryGroup.find_by(owner: @org, group_path: "f")
    sports = T.must(SportsGroupSetting.load_by_group(group))
    assert_equal "f", sports.group_path
    assert_same_elements ["tennis"], sports.value["ball"]
    assert_same_elements ["chess"], sports.value["no_ball"]
  end

  test "load_all_by_group" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "")
    all_settings = RepositoryGroupSetting.load_all_by_group(group)
    paint = T.must(all_settings["RepositoryGroupSettingTest::PaintGroupSetting"])
    sports = all_settings["RepositoryGroupSettingTest::SportsGroupSetting"]
    assert_nil sports
    refute_nil paint
    assert_same_elements ["blue"], paint.composite["colors"]

    group = RepositoryGroup.find_by(owner: @org, group_path: "foo")
    all_settings = RepositoryGroupSetting.load_all_by_group(group)
    paint = T.must(all_settings["RepositoryGroupSettingTest::PaintGroupSetting"])
    sports = all_settings["RepositoryGroupSettingTest::SportsGroupSetting"]
    assert_same_elements %w[blue green], paint.composite["colors"]
    assert_same_elements ["blue"], paint.inherited["colors"]
    assert_same_elements ["green"], paint.value["colors"]
    assert_nil sports

    group = RepositoryGroup.find_by(owner: @org, group_path: "foo/bar")
    all_settings = RepositoryGroupSetting.load_all_by_group(group)
    paint = T.must(all_settings["RepositoryGroupSettingTest::PaintGroupSetting"])
    sports = T.must(all_settings["RepositoryGroupSettingTest::SportsGroupSetting"])
    assert_same_elements %w[blue green purple], paint.composite["colors"]
    assert_same_elements %w[football], sports.composite["ball"]
    assert_same_elements %w[track], sports.composite["no_ball"]

    group = RepositoryGroup.find_by(owner: @org, group_path: "foo/bar/cat")
    all_settings = RepositoryGroupSetting.load_all_by_group(group)
    paint = T.must(all_settings["RepositoryGroupSettingTest::PaintGroupSetting"])
    sports = T.must(all_settings["RepositoryGroupSettingTest::SportsGroupSetting"])
    assert_same_elements %w[blue green purple], paint.composite["colors"]
    assert_same_elements %w[baseball soccer], sports.value["ball"]
    assert_same_elements %w[football], sports.inherited["ball"]
    assert_same_elements %w[football baseball soccer], sports.composite["ball"]
    assert_same_elements %w[track swimming], sports.composite["no_ball"]
  end

  test "load settings" do
    root_group = RepositoryGroup.find_by(owner: @org, group_path: "")
    foo_group = RepositoryGroup.find_by(owner: @org, group_path: "foo")
    food_group = RepositoryGroup.find_by(owner: @org, group_path: "food")
    foobar_group = RepositoryGroup.find_by(owner: @org, group_path: "foo/bar")
    foobarcat_group = RepositoryGroup.find_by(owner: @org, group_path: "foo/bar/cat")

    root = T.must(PaintGroupSetting.load_by_group(root_group))
    foo = T.must(PaintGroupSetting.load_by_group(foo_group))
    food = T.must(PaintGroupSetting.load_by_group(food_group))
    foobar = T.must(PaintGroupSetting.load_by_group(foobar_group))
    foobarcat = T.must(PaintGroupSetting.load_by_group(foobarcat_group))

    assert_equal "", root.group_path
    assert_equal ["blue"], root.value["colors"]
    assert_nil root.inherited["colors"]
    assert_equal %w[blue], root.composite["colors"]

    assert_equal "foo", foo.group_path
    assert_equal ["green"], foo.value["colors"]
    assert_equal %w[blue], foo.inherited["colors"]
    assert_equal %w[blue green], foo.composite["colors"]

    assert_equal "food", food.group_path
    assert_equal ["yellow"], food.value["colors"]
    assert_equal %w[blue], food.inherited["colors"]
    assert_equal %w[blue yellow], food.composite["colors"]

    assert_equal "foo/bar", foobar.group_path
    assert_equal %w[blue purple], foobar.value["colors"]
    assert_equal %w[blue green], foobar.inherited["colors"]
    assert_equal %w[blue green purple], foobar.composite["colors"]

    assert_equal "foo/bar/cat", foobarcat.group_path
    assert_nil foobarcat.value["colors"]
    assert_equal %w[blue green purple], foobarcat.inherited["colors"]
    assert_equal %w[blue green purple], foobarcat.composite["colors"]
  end

  test "no direct setting" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "foo/bar/cat")
    paint = T.must(PaintGroupSetting.load_by_group(group))
    expected = {}
    assert_same_hash expected, paint.value
    expected = { "colors" => %w[blue green purple] }
    assert_same_hash expected, paint.inherited
    assert_same_hash expected, paint.composite
  end

  class PaintGroupSetting < RepositoryGroupSetting
    def populate_attributes
      self.value ||= { "colors": {} }
      self.inherited ||= {}
      self.composite ||= {}
    end

    def apply(actor:, repository:); end
  end

  class SportsGroupSetting < RepositoryGroupSetting
    def populate_attributes
      self.value ||= { "ball": [], "no_ball": [] }
      self.inherited ||= {}
      self.composite ||= {}
    end

    def apply(actor:, repository:); end
  end
end
