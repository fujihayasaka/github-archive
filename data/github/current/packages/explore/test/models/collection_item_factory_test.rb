# typed: true
# frozen_string_literal: true

require "test_helper"

class CollectionItemFactoryTest < GitHub::TestCase
  setup do
    @item_factory = CollectionItemFactory.new
    @collections_repo_owner = create(:organization, login: ExploreRepositoryFileReader::REPO_OWNER)
    @collections_repo = create(:repository, owner: @collections_repo_owner, name: ExploreRepositoryFileReader::REPO_NAME)
    @repo_user = create(:user, login: "test-user")
    @repo = create(:repository, owner: @repo_user, name: "javascript")
  end

  context "Collection item factory" do
    test "does not create a collection item when connection read timeout is throw" do
      stub_request(:get, "https://www.javascriptisfun.com").to_raise(Net::ReadTimeout)
      collection_item = @item_factory.build_from_slug("https://www.javascriptisfun.com")

      assert_predicate collection_item, :nil?
    end

    test "does not create a collection item when connection open timeout is throw" do
      stub_request(:get, "https://www.random.com").to_raise(Net::OpenTimeout)
      collection_item = @item_factory.build_from_slug("https://www.random.com")

      assert_predicate collection_item, :nil?
    end

    test "does not create a collection item when slug is not found" do
      collection_item = @item_factory.build_from_slug("/tmp/runcode")

      assert_predicate collection_item, :nil?
    end

    test "build from youtube video url" do
      VCR.use_cassette "collection/item/youtube" do
        collection_item = @item_factory.build_from_slug("https://www.youtube.com/watch?v=1FbjeL74yWU")

        assert_equal "CollectionVideo", collection_item.content_type
        assert_equal "https://www.youtube.com/embed/1FbjeL74yWU", collection_item.content.url
        assert_equal "https://img.youtube.com/vi/1FbjeL74yWU/0.jpg", collection_item.content.thumbnail_url
        assert_equal "How Does Your Phone Know This Is A Dog?", collection_item.content.title
        assert_includes collection_item.content.description, "Check out this other video about machine learning"
      end
    end

    test "build from youtube embed video url" do
      VCR.use_cassette "collection/item/youtube" do
        collection_item = @item_factory.build_from_slug("https://www.youtube.com/embed/1FbjeL74yWU")

        assert_equal "CollectionVideo", collection_item.content_type
        assert_equal "https://www.youtube.com/embed/1FbjeL74yWU", collection_item.content.url
        assert_equal "https://img.youtube.com/vi/1FbjeL74yWU/0.jpg", collection_item.content.thumbnail_url
        assert_equal "How Does Your Phone Know This Is A Dog?", collection_item.content.title
        assert_includes collection_item.content.description, "Check out this other video about machine learning"
      end
    end

    test "build from youtube embed video url with video start query parameter" do
      VCR.use_cassette "collection/item/youtube" do
        collection_item = @item_factory.build_from_slug("https://www.youtube.com/embed/1FbjeL74yWU?start=1")

        assert_equal "CollectionVideo", collection_item.content_type
        assert_equal "https://www.youtube.com/embed/1FbjeL74yWU?start=1", collection_item.content.url
        assert_equal "How Does Your Phone Know This Is A Dog?", collection_item.content.title
        assert_includes collection_item.content.description, "Check out this other video about machine learning"
      end
    end

    test "build from arbitrary url" do
      VCR.use_cassette "collection/item/website" do
        collection_item = @item_factory.build_from_slug("https://yarnpkg.com/en/")

        assert_equal "CollectionUrl", collection_item.content_type
        assert_equal "https://yarnpkg.com/en/", collection_item.content.url
        assert_equal "Yarn", collection_item.content.title
        assert_equal "Fast, reliable, and secure dependency management.", collection_item.content.description
      end
    end

    test "build from Organization" do
      collection_item = @item_factory.build_from_slug(ExploreRepositoryFileReader::REPO_OWNER)

      assert_equal "User", collection_item.content_type
      assert_equal "github", collection_item.content.login
    end

    test "build Organization from GitHub url" do
      collection_item = @item_factory.build_from_slug("https://www.github.com/#{ExploreRepositoryFileReader::REPO_OWNER}")

      assert_equal "User", collection_item.content_type
      assert_equal "github", collection_item.content.login
    end

    test "build from User" do
      collection_item = @item_factory.build_from_slug("test-user")

      assert_equal "User", collection_item.content_type
      assert_equal "test-user", collection_item.content.login
    end

    test "build User from GitHub url" do
      collection_item = @item_factory.build_from_slug("https://github.com/test-user")

      assert_equal "User", collection_item.content_type
      assert_equal "test-user", collection_item.content.login
    end

    test "build from Repository" do
      collection_item = @item_factory.build_from_slug("test-user/javascript")

      assert_equal "Repository", collection_item.content_type
      assert_equal "javascript", collection_item.content.name
    end

    test "build Repository from GitHub url" do
      collection_item = @item_factory.build_from_slug("https://www.github.com/test-user/javascript")

      assert_equal "Repository", collection_item.content_type
      assert_equal "javascript", collection_item.content.name
    end
  end
end
