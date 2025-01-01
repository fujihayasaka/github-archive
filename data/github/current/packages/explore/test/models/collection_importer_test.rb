# typed: true
# frozen_string_literal: true

require "test_helper"

class CollectionImporterTest < GitHub::TestCase
  setup do
    @item_factory = CollectionItemFactory.new
    @collections_repo_owner = create(:organization, login: ExploreRepositoryFileReader::REPO_OWNER)
    @collections_repo = create(:repository, owner: @collections_repo_owner, name: ExploreRepositoryFileReader::REPO_NAME, from_example: :explore)
    @defunkt_repo_owner = create(:user, login: "defunkt")
    @playground_repo = create(:repository, owner: @defunkt_repo_owner, name: "playground")
    @importer = CollectionImporter.new(ExploreRepositoryFileReader.new("collections"))
    ExploreCollection.destroy_all
  end

  context "#import dry run" do
    test "sets an error if the collections repository does not exist" do
      @collections_repo.destroy

      result = @importer.import(dry_run: true)

      assert_includes result.errors, "Missing public repository #{@collections_repo.nwo}"
    end

    test "sets an error if the latest sha couldn't be found in the collections repository" do
      @collections_repo.destroy
      # Make the repo again, but don't set it up with `example_repo`:
      repo = create(:repository, owner: @collections_repo_owner, name: ExploreRepositoryFileReader::REPO_NAME)

      result = @importer.import(dry_run: true)

      assert_includes result.errors,
        "Could not determine latest commit for #{repo.nwo} in #{repo.default_branch} branch"
    end

    test "returns changeset of new collections, when there are no existing collections" do
      VCR.use_cassette "collection/item/website" do
        result = @importer.import(dry_run: true)

        assert_equal 3, result.new_count
        assert_equal 0, result.updated_count
        assert_equal 0, ExploreCollection.count, "No Collections should be added when ran in dry run mode"
        assert_equal 0, CollectionItem.count, "No Collection items should be added when ran in dry run mode"
      end
    end

    test "returns changeset for deletion" do
      VCR.use_cassette "collection/item/website" do
        item = @item_factory.build_from_slug("github")
        collection = create(:explore_collection, slug: "checkers", display_name: "Checkers")
        collection.items << item

        result = @importer.import(dry_run: true)

        assert_equal 3, result.new_count
        assert_equal 1, result.updated_count
        assert_equal 1, ExploreCollection.count, "No Collections should be added when ran in dry run mode"
        assert_equal 1, CollectionItem.count, "No Collection items should be added when ran in dry run mode"
      end
    end

    test "returns changeset of changed collection" do
      VCR.use_cassette "collection/item/website" do
        create(:explore_collection, slug: "music", description: "I love music")
        result = @importer.import(dry_run: true)

        assert_equal 2, result.new_count
        assert_equal 1, result.updated_count
        assert_equal 1, ExploreCollection.count, "No Collections should be added when ran in dry run mode"
        assert_equal 0, CollectionItem.count, "No Collection items should be added when ran in dry run mode"
      end
    end

    test "returns changeset of changed collection, when items are changed" do
      VCR.use_cassette "collection/item/website" do
        create(:repository, owner: @defunkt_repo_owner, name: "dotjs")

        item = @item_factory.build_from_slug("defunkt/dotjs")
        collection = create(:explore_collection, slug: "music")
        collection.items << item

        result = @importer.import(dry_run: true)
        changes = result.updated_changesets[0].to_h

        assert_equal 2, result.new_count
        assert_equal 1, result.updated_count
        assert_equal "defunkt/dotjs", changes["items"]["old"]
        assert_equal "defunkt/playground, github", changes["items"]["new"]
        assert_equal 1, ExploreCollection.count, "No Collections should be added when ran in dry run mode"
        assert_equal 1, CollectionItem.count, "No Collection items should be added when ran in dry run mode"
      end
    end

    context "#import selected collections" do
      test "saves new selected collection" do
        VCR.use_cassette "collection/item/website" do
          assert_equal 0, ExploreCollection.where(slug: "clean-code-linters").count
          selected_collection = ["clean-code-linters"]

          @importer.import(dry_run: false, collection_slugs: selected_collection)

          actual_collection = ExploreCollection.where(slug: "clean-code-linters")
          item_slugs = T.must(actual_collection.first).items.map(&:slug)

          assert_equal 1, ExploreCollection.count
          assert_equal 1, CollectionItem.count
          assert_equal 1, actual_collection.count
          assert_equal ["https://yarnpkg.com/en/"], item_slugs
        end
      end

      test "saves two selected collections" do
        VCR.use_cassette "collection/item/website" do
          assert_equal 0, ExploreCollection.count
          selected_collections = %w[clean-code-linters machine-learning]

          @importer.import(dry_run: false, collection_slugs: selected_collections)

          actual_collections = ExploreCollection.where(slug: selected_collections)

          assert_equal 2, ExploreCollection.count
          assert_equal 3, CollectionItem.count
          assert_equal 2, actual_collections.count
        end
      end

      test "updates selected collection" do
        VCR.use_cassette "collection/item/website" do
          item = @item_factory.build_from_slug("defunkt/playground")
          collection = create(:explore_collection, slug: "music", created_by: "Clark", display_name: "more music", description: "what")
          collection.items << item

          assert_equal 1, ExploreCollection.count
          assert_equal 1, CollectionItem.count

          selected_collection = ["music"]

          @importer.import(dry_run: false, collection_slugs: selected_collection)
          actual_collection = ExploreCollection.where(slug: "music")
          actual_collection_first = T.must(actual_collection.first)
          item_slugs = actual_collection_first.items.map(&:slug)

          assert_equal 1, ExploreCollection.count
          assert_equal 2, CollectionItem.count
          assert_equal 1, actual_collection.count
          assert_equal "Bruce", actual_collection_first.created_by
          assert_equal "music", actual_collection_first.slug
          assert_equal "Music", actual_collection_first.display_name
          assert_equal "Drop the code bass with these musically themed repositories.",
            actual_collection_first.description
          assert_equal ["defunkt/playground", "github"], item_slugs
        end
      end

      test "deletes selected collection not in collections repo" do
        VCR.use_cassette "collection/item/website" do
          item = @item_factory.build_from_slug("github")
          collection = create(:explore_collection, slug: "checkers", display_name: "Checkers")
          collection.items << item

          assert_equal 1, ExploreCollection.where(slug: "checkers").count
          assert_equal 1, CollectionItem.count

          @importer.import(dry_run: false, collection_slugs: ["checkers"])

          assert_equal 0, ExploreCollection.where(slug: "checkers").count
          assert_equal 0, CollectionItem.count
        end
      end

      test "reimports selected collection when unchanged" do
        VCR.use_cassette "collection/item/website", allow_playback_repeats: true do
          @importer.import(dry_run: false, collection_slugs: ["clean-code-linters"])
          collection = ExploreCollection.where(slug: "clean-code-linters").first
          #collection item's title and description are not checked for changes
          item_content = T.must(T.must(collection).items.first).content
          item_content.description = "updated description"
          item_content.save

          @importer.import(dry_run: false, collection_slugs: ["clean-code-linters"], force_import: true)

          collection = ExploreCollection.where(slug: "clean-code-linters").first
          item = T.must(collection).items.first
          description = T.must(item).content.description
          assert_equal "Fast, reliable, and secure dependency management.", description
        end
      end

      test "does not reimport selected collection when unchanged" do
        VCR.use_cassette "collection/item/website", allow_playback_repeats: true do
          @importer.import(dry_run: false, collection_slugs: ["clean-code-linters"])
          collection = ExploreCollection.where(slug: "clean-code-linters").first
          #collection item's title and description are not checked for changes
          item_content = T.must(T.must(collection).items.first).content
          item_content.description = "updated description"
          item_content.save

          @importer.import(dry_run: false, collection_slugs: ["clean-code-linters"])

          collection = ExploreCollection.where(slug: "clean-code-linters").first
          item = T.must(collection).items.first
          description = T.must(item).content.description
          assert_equal "updated description", description
        end
      end
    end
  end
end
