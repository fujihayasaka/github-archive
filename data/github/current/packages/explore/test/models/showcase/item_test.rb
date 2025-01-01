# typed: true
# frozen_string_literal: true

require "test_helper"

class ShowcaseItemTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  test "requires an repo" do
    item = Showcase::Item.create
    item.valid?

    assert_equal "can't be blank", item.errors[:item_id].first
  end

  test "primary language handles repo being deleted gracefully" do
    item = Showcase::Item.create(item: @repo)

    @repo.destroy
    assert_nil item.primary_language
  end

  test "knows about its showcase" do
    list = create :showcase_collection
    item = list.items.create(item: @repo)

    assert_equal list, item.showcase
  end

  context ".sorted_by" do
    test "sorted for stars" do
      repo_1 = create(:repository, stargazer_count: 5)
      repo_2 = create(:repository, stargazer_count: 10)

      item_1 = Showcase::Item.create(item: repo_1)
      item_2 = Showcase::Item.create(item: repo_2)

      assert_equal [item_2, item_1], Showcase::Item.sorted_by(:stars)
    end

    test "sorted for languages" do
      language_aaa = create(:language_name, name: "aaa")
      language_zzz = create(:language_name, name: "zzz")

      repo_1 = create(:repository, primary_language_name_id: language_zzz.id)
      repo_2 = create(:repository, primary_language_name_id: language_aaa.id)

      item_1 = Showcase::Item.create(item: repo_1)
      item_2 = Showcase::Item.create(item: repo_2)

      assert_equal [item_2, item_1], Showcase::Item.sorted_by(:language)
    end

    test "sorted for featured default" do
      repo_1 = create(:repository)
      repo_2 = create(:repository)

      item_1 = Showcase::Item.create(item: repo_1, created_at: 2.weeks.ago)
      item_2 = Showcase::Item.create(item: repo_2, created_at: 1.week.ago)

      assert_equal [item_1, item_2], Showcase::Item.sorted_by(:featured)
    end
  end
end
