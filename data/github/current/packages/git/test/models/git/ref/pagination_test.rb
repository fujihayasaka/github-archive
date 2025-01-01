# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class GitRefCollectionPaginationTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :simple)

    # ["v4", "v3", "v2", "v1", "v0"]
    @paginated_repo = create :repository, from_example: :paginated_tags

    example_repo_snapshot
  end

  setup do
    Spokesd.enable_spokesd

    example_repo_restore
  end

  context "#page" do
    test "when no params" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/tags/")

      assert_equal %w(v1 v2), collection.page.map(&:name)
    end

    test "test page when after defined" do
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/tags/")

      assert_equal %w(v2), collection.page(after: "v1").map(&:name)
    end

    test "test page when after param is unicode" do
      unicode_tag = Git::Ref.new(@repo, "refs/tags/v1.λ.2").create(@repo.default_oid, @repo.owner)
      collection = Git::Ref::Collection.new(loader: Git::Ref::Loader.new(@repo, "default"), prefix: "refs/tags/")

      assert_equal %w(v2), collection.page(after: unicode_tag.name).map(&:name)
    end
  end

  # ["v4", "v3", "v2", "v1", "v0"]
  context "#paginate" do
    test "without valid 'after' tag" do
      pag = @paginated_repo.sorted_tags.paginate("whatevs", 2, 2)
      assert_equal 3, pag.page_count, pag.inspect
      assert_equal 1, pag.current_page, pag.inspect
      assert_equal "v3", pag.next_tag, pag.inspect
      assert_nil pag.previous_tag, pag.inspect
      refute pag.previous_page?, pag.inspect
      assert pag.next_page?, pag.inspect
    end

    test "with valid 'after' tag" do
      pag = @paginated_repo.sorted_tags.paginate("v3", 2, 2)
      assert_equal 3, pag.page_count, pag.inspect
      assert_equal 1, pag.current_page, pag.inspect
      assert_equal "v3", pag.next_tag, pag.inspect
      assert_nil pag.previous_tag, pag.inspect
      refute pag.previous_page?, pag.inspect
      assert pag.next_page?, pag.inspect
    end

    test "with valid 'after' tag on middle page" do
      pag = @paginated_repo.sorted_tags.paginate("v1", 2, 2)
      assert_equal 3, pag.page_count, pag.inspect
      assert_equal 2, pag.current_page, pag.inspect
      assert_equal "v1", pag.next_tag, pag.inspect
      assert_nil pag.previous_tag, pag.inspect
      assert pag.previous_page?, pag.inspect
      assert pag.next_page?, pag.inspect
    end

    test "with valid 'after' tag on last page" do
      pag = @paginated_repo.sorted_tags.paginate("v0", 2, 2)
      assert_equal 3, pag.page_count, pag.inspect
      assert_equal 3, pag.current_page, pag.inspect
      assert_nil pag.next_tag, pag.inspect
      assert_equal "v4", pag.previous_tag, pag.inspect
      assert pag.previous_page?, pag.inspect
      refute pag.next_page?, pag.inspect
    end
  end
end
