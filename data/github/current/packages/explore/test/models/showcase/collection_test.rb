# typed: true
# frozen_string_literal: true

require "test_helper"

class ShowcaseCollectionTest < GitHub::TestCase

  fixtures do
    @list = create :showcase_collection
  end

  test "requires a name" do
    list = Showcase::Collection.new
    list.valid?

    assert_equal "can't be blank", list.errors[:name].first
  end

  test "generates a slug" do
    assert_equal "android-essentials", @list.slug
  end

  test "generates a unique slug" do
    sequel = Showcase::Collection.new name: "Android Essentials"
    sequel.save

    assert_equal "android-essentials-1", sequel.slug
  end

  test "doesn't try to update the slug to a duplicate of itself" do
    @list.save
    assert_equal "android-essentials", @list.slug
  end

  test "doesn't update the slug if the collection is published" do
    @list.update_attribute(:published, true)
    @list.name = "More Android Essentials"
    @list.valid?

    assert_equal "android-essentials", @list.slug
  end

  test "does set the slug if the collection is published when created" do
    more = Showcase::Collection.new name: "More Android Essentials", published: true
    more.valid?
    assert_equal "more-android-essentials", more.slug
  end

  test "#languages" do
    ruby = create(:ruby_language_name)
    js = create(:javascript_language_name)
    repo = create(:repository, primary_language: ruby)
    repo2 = create(:repository, primary_language: ruby)
    repo3 = create(:repository, primary_language: js)

    @list.items.create(item: repo)
    @list.items.create(item: repo2)
    @list.items.create(item: repo3)
    assert_equal([ruby, js].sort, @list.languages.sort)
  end

  test "languages handles deleted item items correctly" do
    repo  = create(:repository)

    @list.items.create(item: repo)
    repo.destroy
    assert_empty @list.languages
  end
end
