# typed: true
# frozen_string_literal: true

require "test_helper"

class SiteFeaturesTest < GitHub::TestCase
  context ".data" do
    test "loads data from the data file" do
      stubbed_yaml = YAML::load <<~YAML
        ---
        - title: "Green eggs and YAML"
      YAML

      YAML.expects(:load_file).with(Site::Features::DATA_PATH).once.returns(stubbed_yaml)

      Site::Features.data

      YAML.unstub(:load_file)
    end

    test "only loads the file once" do
      stubbed_yaml = YAML::load <<~YAML
        ---
        - title: "Once upon a YAML..."
      YAML

      YAML.expects(:load_file).with(Site::Features::DATA_PATH).once.returns(stubbed_yaml)

      Site::Features.data
      Site::Features.data

      YAML.unstub(:load_file)
    end
  end

  context ".category_item_collections" do
    test "returns a list of category item collections with items" do
      stubbed_yaml = YAML::load <<~YAML
        ---
        - id: "automation"
          items:
          - title: "One lonely item"
            description: "Something odd about this item"
      YAML

      Site::Features.stub(:data, stubbed_yaml) do
        result = Site::Features.category_item_collections

        assert_equal result.class, Array
        assert_equal result[0].class, Site::Features::CategoryItemCollection
        assert_equal result[0].id, "automation"
        assert_equal result[0].items.class, Array
        assert_equal result[0].items[0].class, Site::Features::CategoryItemCollection::Item
        assert_equal result[0].items[0].title, "One lonely item"
        assert_equal result[0].items[0].description, "Something odd about this item"
      end
    end
  end

  context ".find_category_item_collection" do
    test "gets a category item collection via provided id" do
      stubbed_yaml = YAML::load <<~YAML
        ---
        - id: "automation"
          items:
          - title: "First automation item"
            description: "Something odd about this item"
        - id: "security"
          items:
          - title: "I feel safe!"
            description: "Something else about this item"
          - title: "Second security item"
            description: "This is just another item"
      YAML

      Site::Features.stub(:data, stubbed_yaml) do
        result = Site::Features.find_category_item_collection("security")

        assert_equal result.class, Site::Features::CategoryItemCollection
        assert_equal result.id, "security"
        assert_equal result.items.class, Array
        assert_equal result.items.length, 2
        assert_equal result.items[0].class, Site::Features::CategoryItemCollection::Item
        assert_equal result.items[0].title, "I feel safe!"
        assert_equal result.items[0].description, "Something else about this item"
      end
    end
  end
end

class SiteFeaturesCategoryItemCollectionTest < GitHub::TestCase
  context "#new" do
    test "creates an empty new category item collection" do
      data = {
        id: "foundation"
      }

      category = Site::Features::CategoryItemCollection.new(id: data[:id], items: [])

      assert_equal category.id, "foundation"
      assert_equal category.items.class, Array
      assert_empty category.items
    end

    test "creates a new category item collection with items that are passed in" do
      items = [{
          title: "Public Repos",
          description: "Public repos!",
          button_link: "#",
          button_class: "less-amazing-button",
        },
        {
          title: "Issues",
          description: "Issues!",
          button_link: "/foo",
          button_class: "less-amazing-button",
        }
      ]

      data = {
        id: "foundation",
        items: items.map { |item| Site::Features::CategoryItemCollection::Item.new(item.symbolize_keys) }
      }

      category = Site::Features::CategoryItemCollection.new(**data)

      assert_equal category.id, "foundation"
      assert_equal category.items.class, Array
      assert_equal category.items.length, 2
      assert_equal category.items[1].class, Site::Features::CategoryItemCollection::Item
      assert_equal T.must(category.items[1]).title, "Issues"
      assert_equal T.must(category.items[1]).description, "Issues!"
      assert_equal T.must(category.items[1]).button_link, "/foo"
      assert_equal T.must(category.items[1]).button_class, "less-amazing-button"
    end
  end
end

class SiteFeaturesCategoryItemTest < GitHub::TestCase
  context "#new" do
    test "returns an item with attributes" do
      data = {
        title: "Public Repos",
        description: "Public repos!",
        button_link: "#",
        button_class: "amazing-button"
      }

      item = Site::Features::CategoryItemCollection::Item.new(data)

      assert_equal item.title, "Public Repos"
      assert_equal item.description, "Public repos!"
      assert_equal item.button_link, "#"
      assert_equal item.button_class, "amazing-button"
    end
  end
end
