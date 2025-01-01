# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexesDependencyTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @org = create(:business_plus_organization, admin: @user)
    @org_repo = create(:repository, owner: @org)
    @memex = create(:memex_project, owner: @org)
    @memex2 = create(:memex_project, owner: @org, public: true)
    @deleted_memex = create(:memex_project, owner: @org, public: true, deleted_at: Time.now)
    @closed_memex = create(:memex_project, owner: @org, public: true, closed_at: Time.now)
    create(:memex_project_link, source: @org_repo, memex_project: @memex)
    create(:memex_project_link, source: @org_repo, memex_project: @memex2)
    create(:memex_project_link, source: @org_repo, memex_project: @deleted_memex)
    create(:memex_project_link, source: @org_repo, memex_project: @closed_memex)
  end

  setup do
    GitHub.cache.allow = /.*/
    GitHub.cache.clear
  end

  context "#open_memex_projects_count_for" do
    test "returns 0 when there are not projects linked" do
      new_org_repo = create(:repository, owner: @org)
      assert_equal 0, new_org_repo.open_memex_projects_count_for(@user)
    end

    test "returns only public projects for non-members" do
      non_member = create(:user)

      assert_equal 1, @org_repo.open_memex_projects_count_for(non_member)
    end

    test "returns memex projects count" do
      assert_equal 2, @org_repo.open_memex_projects_count_for(@user)
    end

    test "caching projects count" do
      assert_equal 2, @org_repo.open_memex_projects_count_for(@user)

      memex_projects_ids = @org_repo.memex_project_links.pluck(:memex_project_id)
      open_memex_projects_ids = MemexProject.where(id: memex_projects_ids).open_projects.order(:id).pluck(:id)
      memexes_ids_hash = Digest::SHA256.hexdigest open_memex_projects_ids.join(",")
      key = "open_memex_projects_count:v1:#{@org_repo.id}:#{@user.id}:#{memexes_ids_hash}"

      assert_equal 2, GitHub.cache.get(key)
    end

    test "caching projects count with anonymous user" do
      assert_equal 1, @org_repo.open_memex_projects_count_for(nil)
      assert_equal 1, GitHub.dogstats.increments("open_memex_projects_count.cache.miss", tags: ["action:open_memex_projects_count"]).count

      memex_projects_ids = @org_repo.memex_project_links.pluck(:memex_project_id)
      open_memex_projects_ids = MemexProject.where(id: memex_projects_ids).open_projects.order(:id).pluck(:id)
      memexes_ids_hash = Digest::SHA256.hexdigest open_memex_projects_ids.join(",")
      key = "open_memex_projects_count:v1:#{@org_repo.id}:anon:#{memexes_ids_hash}"

      assert_equal 1, GitHub.cache.get(key)

      assert_equal 1, @org_repo.open_memex_projects_count_for(nil)
      assert_equal 1, GitHub.dogstats.increments("open_memex_projects_count.cache.hit", tags: ["action:open_memex_projects_count"]).count
      assert_equal 1, GitHub.dogstats.increments("open_memex_projects_count.cache.miss", tags: ["action:open_memex_projects_count"]).count
    end

    test "invalidating cache when links are updated" do
      assert_equal 2, @org_repo.open_memex_projects_count_for(@user)
      assert_equal 1, GitHub.dogstats.increments("open_memex_projects_count.cache.miss", tags: ["action:open_memex_projects_count"]).count

      memex3 = create(:memex_project, owner: @org)
      link = create(:memex_project_link, source: @org_repo, memex_project: memex3)
      # Needed to reset memoized value
      @org_repo = Repository.find(@org_repo.id)

      assert_equal 3, @org_repo.open_memex_projects_count_for(@user)
      assert_equal 2, GitHub.dogstats.increments("open_memex_projects_count.cache.miss", tags: ["action:open_memex_projects_count"]).count

      link.destroy
      @org_repo = Repository.find(T.must(@org_repo.id))

      assert_equal 2, @org_repo.open_memex_projects_count_for(@user)
    end

    test "invalidating cache when projects are closed" do
      assert_equal 2, @org_repo.open_memex_projects_count_for(@user)
      assert_equal 1, GitHub.dogstats.increments("open_memex_projects_count.cache.miss", tags: ["action:open_memex_projects_count"]).count

      @memex2.update(closed_at: Time.now)
      # Needed to reset memoized value
      @org_repo = Repository.find(@org_repo.id)

      assert_equal 1, @org_repo.open_memex_projects_count_for(@user)
      assert_equal 2, GitHub.dogstats.increments("open_memex_projects_count.cache.miss", tags: ["action:open_memex_projects_count"]).count

      @memex2.update(closed_at: nil)
      @org_repo = Repository.find(T.must(@org_repo.id))

      assert_equal 2, @org_repo.open_memex_projects_count_for(@user)
    end
  end
end
