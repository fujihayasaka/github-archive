# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectsDependencyOrgTest < GitHub::TestCase
  include MemexHelpers
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @org_member = create(:verified_user).tap { |u| @org.add_member(u) }
    @non_org_member = create(:verified_user)

    # Site admin viewer
    @site_admin_member = create(:staff_admin_user)
    @org.add_member(@site_admin_member)

    @memexes = [
      create(:memex_project, owner: @org, title: "abc", creator: @admin),
      create(:memex_project, owner: @org, title: "abcde", creator: @admin),
      create(:memex_project, owner: @org, title: "def", creator: @admin),
      create(:memex_project, owner: @org, title: "defgh", creator: @admin, closed_at: 1.day.ago),
      create(:memex_project, owner: @org, title: "tuv", creator: @org_member),
      create(:memex_project, owner: @org, title: "wxyz", creator: @org_member, closed_at: 2.days.ago),
      create(:memex_project, owner: @org, title: nil, creator: @org_member, closed_at: 3.days.ago),
      create(:memex_project, owner: @org, title: "wxyz", creator: @org_member, deleted_at: 4.days.ago),
      create(:memex_project, owner: @org, title: "wxyz", creator: @org_member, deleted_at: 5.days.ago, closed_at: 6.days.ago),
    ]

    # test setup for a IntegrationInstallation (org-wide GitHub App)
    @read_org_integration = create(:integration,
      :with_active_hook,
      default_permissions: { "organization_projects" => :read }
    )
    @write_org_integration = create(:integration,
      :with_active_hook,
      default_permissions: { "organization_projects" => :write }
    )

    @org_read_installation = make_integration_installation(target: @org, integration: @read_org_integration)
    @org_write_installation = make_integration_installation(target: @org, integration: @write_org_integration)

    # test setup for a ScopedIntegrationInstallation (targeting org and set of repositories within org)
    # access should be the same given Memex projects are not associated with a repository
    @org_repo = create(:private_repository, owner: @org)

    @org_and_repo_read_installation = make_scoped_integration_installation(
      parent:  @org_read_installation,
      repositories: [@org_repo],
    )

    @org_and_repo_write_installation = make_scoped_integration_installation(
      parent:  @org_write_installation,
      repositories: [@org_repo],
    )

    # test setup for a SiteScopedIntegrationInstallation (special internal apps that need to work across all orgs and users)
    @site_read_integration = create_unlimited_global_integration(permissions: {  "organization_projects" => :read })
    @site_write_integration = create_unlimited_global_integration(permissions: {  "organization_projects" => :write })

    @org_site_read_installation = make_integration_installation(target: @org, integration: @site_read_integration)
    @org_site_write_installation = make_integration_installation(target: @org, integration: @site_write_integration)

    MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
  end

  context "#search_memex_projects" do
    test "returns a page of results for open memexes by default (for a blank query)" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new(""),
        viewer: @admin
      )
      assert_equal %w[tuv def abcde abc], result.memex_projects.map(&:title)
    end

    test "applies a state filter when it is present in the query" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:closed"),
        viewer: @admin
      )
      assert_equal [nil, "wxyz", "defgh"], result.memex_projects.map(&:title)
    end

    test "applies a creator filter when it is present in the query" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("creator:#{@org_member}"),
        viewer: @admin
      )
      # Note that "is:open" is the implicit state filter in the query. This is because the view
      # presented to users is always segmented by state, so we use "is:open" as the default.
      assert_equal ["tuv"], result.memex_projects.map(&:title)

      # However, we still return an accurate closed count if "is:open" isn't explicitly specified.
      assert_equal 2, result.total_closed_count
    end

    test "applying multiple creator filters does not execute query" do
      assert_query_count(0, ignore_feature_flags: true) do
        result = @org.search_memex_projects(
          query: Search::Queries::MemexProjectQuery.new("creator:#{@admin} creator:#{@org_member}"),
          viewer: @admin
        )

        assert_empty result.memex_projects
        assert_equal 0, result.total_open_count
        assert_equal 0, result.total_closed_count
      end
    end

    test "supports @me macro in the creator filter" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:open creator:@me"),
        viewer: @admin
      )
      assert_equal %w[def abcde abc], result.memex_projects.map(&:title)
    end

    test "supports @me macro in the creator filter without viewer" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:open creator:@me"),
        viewer: nil,
      )
      assert_equal [], result.memex_projects
    end

    test "applies a full-text search when it is present in the query" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:open de"),
        viewer: @admin
      )
      assert_equal %w[def abcde], result.memex_projects.map(&:title)

      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:closed de"),
        viewer: @admin
      )
      assert_equal ["defgh"], result.memex_projects.map(&:title)
    end

    test "applies a full-text search using the first word of a query string by default" do
      one = create(:memex_project, owner: @org, title: "hello world", creator: @admin),
      two = create(:memex_project, owner: @org, title: "hello friend", creator: @admin),

      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:open hello world"),
        viewer: @admin
      )

      assert_equal ["hello friend", "hello world"], result.memex_projects.map(&:title)
    end

    test "applies a full-text search using the entire query string when use_full_term_query is true" do
      one = create(:memex_project, owner: @org, title: "hello world", creator: @admin),
      two = create(:memex_project, owner: @org, title: "hello friend", creator: @admin),

      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:open hello world"),
        viewer: @admin,
        use_full_term_query: true
      )

      assert_equal ["hello world"], result.memex_projects.map(&:title)
    end

    test "supports full-text search against the default memex title for untitled memexes" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:closed #{MemexProject::DEFAULT_TITLE}"),
        viewer: @admin
      )

      assert_equal [MemexProject::DEFAULT_TITLE], result.memex_projects.map(&:display_title)
    end

    test "can filter based on template status" do
      template = @memexes.first
      template.create_template!

      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:template"),
        viewer: @admin
      )

      assert_equal [template.display_title], result.memex_projects.map(&:display_title)
    end

    test "supports querying closed template projects" do
      memex = create(:memex_project, owner: @org, title: "template project", creator: @admin)
      memex.create_template!
      memex.update!(closed_at: 1.day.ago)

      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:template is:closed"),
        viewer: @admin
      )

      assert_equal [memex.id], result.memex_projects.map(&:id)
    end

    test "can apply template filter with visibility filters" do
      public_template = @memexes.first
      public_template.update!(public: true)
      public_template.create_template!
      private_template = @memexes.second
      private_template.create_template!

      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:template is:public"),
        viewer: @admin
      )

      assert_predicate public_template, :public?
      refute_predicate private_template, :public?
      assert_equal [public_template.id], result.memex_projects.map(&:id)
    end

    test "applying both open and closed filters does not filter by state" do
      assert_query_count(0, ignore_feature_flags: true) do
        result = @org.search_memex_projects(
          query: Search::Queries::MemexProjectQuery.new("is:open is:closed"),
          viewer: @admin,
        )

        assert_empty result.memex_projects
        assert_equal 0, result.total_open_count
        assert_equal 0, result.total_closed_count
      end
    end

    test "applying both public and private filters cancels out the query" do
      assert_query_count(0, ignore_feature_flags: true) do
        result = @org.search_memex_projects(
          query: Search::Queries::MemexProjectQuery.new("is:public is:private"),
          viewer: @admin
        )

        assert_empty result.memex_projects
        assert_equal 0, result.total_open_count
        assert_equal 0, result.total_closed_count
      end
    end

    test "can apply a state filter and visibility filter" do
      open_project = @memexes.first
      open_project.update!(public: true)
      closed_project = @memexes.second
      closed_project.update!(public: true, closed_at: 1.day.ago)

      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:open is:public"),
        viewer: @admin,
      )

      assert_predicate open_project, :public?
      refute_predicate open_project, :closed?
      assert_predicate closed_project, :public?
      assert_predicate closed_project, :closed?
      assert_equal [open_project.id], result.memex_projects.map(&:id)
    end

    test "returns a correct page metadata" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("creator:#{@admin} de"),
        viewer: @admin,
        cursor: @memexes.third.number,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal @memexes.second.number, result.next_page_cursor
      assert_equal 2, result.total_open_count
      assert_equal 0, result.total_closed_count
    end

    test "returns correct data for created_at queries" do
      admin = create(:verified_user)
      org = create(:organization, admin: admin)
      memexes = [
        create(:memex_project, owner: org, title: "abc", creator: admin, created_at: 1.day.ago),
        create(:memex_project, owner: org, title: "abc", creator: admin, created_at: 2.days.ago),
        create(:memex_project, owner: org, title: "abc", creator: admin, created_at: 3.days.ago),
        create(:memex_project, owner: org, title: "abc", creator: admin, created_at: 4.days.ago),
      ]

      result = org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:created-desc"),
        viewer: admin,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.second.number, result.next_page_cursor
      assert_equal 4, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:created-desc"),
        viewer: admin,
        cursor: memexes.second.number,
        sort_query_cursor: memexes.second.created_at.to_s,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.third.number, result.next_page_cursor
      assert_equal 3, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:created-asc"),
        viewer: admin,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.third.number, result.next_page_cursor
      assert_equal 4, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:created-asc"),
        viewer: admin,
        limit: 1,
        cursor: memexes.third.number,
        sort_query_cursor: memexes.third.created_at.to_s
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.second.number, result.next_page_cursor
      assert_equal 3, result.total_open_count
      assert_equal 0, result.total_closed_count
    end

    test "returns correct data for updated_at queries" do
      admin = create(:verified_user)
      org = create(:organization, admin: admin)
      memexes = 4.times.map do |n|
        Timecop.freeze(n.days.ago) do
          create(:memex_project, owner: org, title: "abc-#{n + 1}")
        end
      end

      result = org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:updated-desc"),
        viewer: admin,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.second.number, result.next_page_cursor
      assert_equal 4, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:updated-desc"),
        viewer: admin,
        cursor: memexes.second.number,
        sort_query_cursor: memexes.second.updated_at.to_s,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.third.number, result.next_page_cursor
      assert_equal 3, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:updated-asc"),
        viewer: admin,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.third.number, result.next_page_cursor
      assert_equal 4, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:updated-asc"),
        viewer: admin,
        limit: 1,
        cursor: memexes.third.number,
        sort_query_cursor: memexes.third.updated_at.to_s
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.second.number, result.next_page_cursor
      assert_equal 3, result.total_open_count
      assert_equal 0, result.total_closed_count
    end

    test "returns correct data for title queries" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("creator:#{@admin} de sort:title-asc"),
        viewer: @admin,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal @memexes.third.number, result.next_page_cursor
      assert_equal @memexes.third.title, result.sort_query_cursor
      assert_equal 2, result.total_open_count
      assert_equal 1, result.total_closed_count

      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("creator:#{@admin} de sort:title-asc"),
        viewer: @admin,
        cursor: @memexes.third.number,
        sort_query_cursor: @memexes.third.title,
        limit: 1
      )

      refute_predicate result, :has_next_page?
      assert_nil result.next_page_cursor
      assert_equal 1, result.total_open_count
      assert_equal 1, result.total_closed_count
    end
  end

  context "#search_memex_projects using FGPs" do
    test "returns a page of results for open memexes by default (for a blank query, for org admin)" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new(""),
        viewer: @admin,
      )
      assert_equal %w[tuv def abcde abc], result.memex_projects.map(&:title)
    end

    test "returns a page of results for open memexes by default (for a blank query, for non org member)" do
      skip "skip this test until we allow outside collaborators"

      @memexes[0].grant_role(@non_org_member, :reader)
      @memexes[3].grant_role(@non_org_member, :reader)

      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new(""),
        viewer: @non_org_member,
      )
      assert_equal ["abc"], result.memex_projects.map(&:title)
    end

    test "applies a state filter when it is present in the query" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:closed"),
        viewer: @admin,
      )
      assert_equal [nil, "wxyz", "defgh"], result.memex_projects.map(&:title)
    end

    test "applies a creator filter when it is present in the query" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("creator:#{@org_member}"),
        viewer: @admin
      )
      # Note that "is:open" is the implicit state filter in the query. This is because the view
      # presented to users is always segmented by state, so we use "is:open" as the default.
      assert_equal ["tuv"], result.memex_projects.map(&:title)

      # However, we still return an accurate closed count if "is:open" isn't explicitly specified.
      assert_equal 2, result.total_closed_count
    end

    test "returns a pages of results for memexes created by @me" do
      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("creator:@me"),
        viewer: @admin,
        limit: 2,
      )
      assert_equal %w[def abcde], result.memex_projects.map(&:title)
      assert_equal 3, result.total_open_count
      assert_equal 1, result.total_closed_count

      result = @org.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("creator:@me"),
        viewer: @admin,
        cursor: result.next_page_cursor,
        limit: 2,
      )
      assert_equal ["abc"], result.memex_projects.map(&:title)
    end
  end

  context "#accessible_memexes_scope" do
    test "returns all memex projects to org admins" do
      assert_accessible_memexes_equal(7, @org, @admin)
    end

    test "returns only public memex projects for non members" do
      create(:memex_project, owner: @org, title: "abcde", public: true)
      assert_accessible_memexes_equal(1, @org, @non_org_member)
    end

    test "returns only public memex projects for anonymous user" do
      create(:memex_project, owner: @org, title: "abcde", public: true)
      assert_accessible_memexes_equal(1, @org, nil)
    end

    test "returns only projects user has explicit access to and public projects" do
      # Disable org wide access for all memexes
      @memexes.each do |memex|
        MemexHelpers::setup_organization_wide_access("none", memex)
      end

      @memexes[0].grant_role(@org_member, :reader)

      @memexes[1].grant_role(@org_member, :reader)

      # Defaults to org wide access
      create(:memex_project, owner: @org, title: "abcde", public: true)

      assert_accessible_memexes_equal(3, @org, @org_member)
    end

    test "returns public projects and private org projects for github app" do
      create(:memex_project, owner: @org, title: "abcde", public: true)
      assert_accessible_memexes_equal(8, @org, @org_read_installation.bot, :read)
    end

    test "returns public projects and private org projects for scoped github app" do
      create(:memex_project, owner: @org, title: "abcde", public: true)
      assert_accessible_memexes_equal(8, @org, @org_and_repo_read_installation.bot, :read)
    end

    test "returns public projects and private org projects for site scoped github app" do
      create(:memex_project, owner: @org, title: "abcde", public: true)
      assert_accessible_memexes_equal(8, @org, @org_site_read_installation.bot, :read)
    end

    context "test write level permissions" do
      test "does not return any projects for anonymous" do
        create(:memex_project, owner: @org, title: "abcde", public: true)
        assert_accessible_memexes_equal(0, @org, nil, "write")
      end

      test "does not return any projects for non member" do
        create(:memex_project, owner: @org, title: "abcde", public: true)
        assert_accessible_memexes_equal(0, @org, @non_org_member, "write")
      end

      test "returns both private and public projects for a member" do
        create(:memex_project, owner: @org, title: "public", public: true)
        assert_accessible_memexes_equal(8, @org, @org_member, "write")
      end

      test "does not return public memex projects for anonymous user" do
        create(:memex_project, owner: @org, title: "abcde", public: true)
        assert_accessible_memexes_equal(0, @org, nil, "write")
      end

      test "returns public projects and private org projects for github app" do
        create(:memex_project, owner: @org, title: "abcde", public: true)
        assert_accessible_memexes_equal(8, @org, @org_write_installation.bot, :write)
      end

      test "returns public projects and private org projects for scoped github app" do
        create(:memex_project, owner: @org, title: "abcde", public: true)
        assert_accessible_memexes_equal(8, @org, @org_and_repo_write_installation.bot, :write)
      end

      test "returns public projects and private org projects for site scoped github app" do
        create(:memex_project, owner: @org, title: "abcde", public: true)
        assert_accessible_memexes_equal(8, @org, @org_site_write_installation.bot, :write)
      end

      test "returns public projects and private org projects excluding soft deleted projects" do
        org = create(:organization, admin: @admin)
        org_member = create(:verified_user).tap { |u| org.add_member(u) }

        memex_1 = create(:memex_project, owner: org, title: "abcde", public: true)
        memex_2 = create(:memex_project, owner: org, title: "fghij", public: true)
        memex_3 = create(:memex_project, owner: org, title: "klmno")

        refute memex_3.public?

        memex_2.soft_delete!(org_member)
        assert_accessible_memexes_equal(2, org, org_member, "read")

        result = org.accessible_memexes_scope(org.memex_projects, org_member, "read", :enumeration)
        assert_same_elements [memex_1, memex_3], result, "result should include memex_1 (public) project and memex_3 (private) project"
        assert_empty [memex_2.id] & result.map(&:id), "result should not include memex_2 (soft deleted) project"
      end
    end

    test "throws an error if permission level is invalid" do
      create(:memex_project, owner: @org, title: "abcde", public: true)
      assert_raises(StandardError, "Unknown auth method: invalid_level") do
        result = @org.accessible_memexes_scope(@org.memex_projects.active_projects, @org_member, :read, :invalid_level)
      end
    end
  end

  context "#recently_visited_projects" do
    test "returns nil when no viewer is provided" do
      refute @org.recently_visited_projects(viewer: nil, cap_filter: cap_authorizing_filter)
    end

    test "returns [] when the viewer has not viewed any projects" do
      assert_equal [], @org.recently_visited_projects(viewer: @org_member, cap_filter: cap_authorizing_filter)
    end

    test "returns a list of memex projects that the user has viewed, in order of viewing" do
      MemexProjectVisit.create({
        viewer_id: @org_member.id,
        memex_project_id: @memexes.first.id,
        last_visited_at: 2.days.ago,
        owner_id: @memexes.first.owner.id,
        owner_type: @memexes.first.owner.type
      })
      MemexProjectVisit.create({
        viewer_id: @org_member.id,
        memex_project_id: @memexes.second.id,
        last_visited_at: 1.day.ago,
        owner_id: @memexes.second.owner.id,
        owner_type: @memexes.second.owner.type
      })

      assert_equal [@memexes.second.title, @memexes.first.title], @org.recently_visited_projects(viewer: @org_member, cap_filter: cap_authorizing_filter).map(&:title)
    end

    test "respects the limit provided" do
      MemexProjectVisit.create({
        viewer_id: @org_member.id,
        memex_project_id: @memexes.first.id,
        last_visited_at: 2.days.ago,
        owner_id: @memexes.first.owner.id,
        owner_type: @memexes.first.owner.type
      })
      MemexProjectVisit.create({
        viewer_id: @org_member.id,
        memex_project_id: @memexes.second.id,
        last_visited_at: 1.day.ago,
        owner_id: @memexes.second.owner.id,
        owner_type: @memexes.second.owner.type
      })

      assert_equal [@memexes.second.title], @org.recently_visited_projects(viewer: @org_member, cap_filter: cap_authorizing_filter, limit: 1).map(&:title)
    end

    test "does not return projects a user cannot access" do
      MemexProjectVisit.create({
        viewer_id: @non_org_member.id,
        memex_project_id: @memexes.first.id,
        last_visited_at: 2.days.ago,
        owner_id: @memexes.first.owner.id,
        owner_type: @memexes.first.owner.type
      })
      MemexProjectVisit.create({
        viewer_id: @non_org_member.id,
        memex_project_id: @memexes.second.id,
        last_visited_at: 1.day.ago,
        owner_id: @memexes.second.owner.id,
        owner_type: @memexes.second.owner.type
      })

      assert_equal [], @org.recently_visited_projects(viewer: @non_org_member, cap_filter: cap_authorizing_filter).map(&:title)
    end

    test "only returns project passing cap_filter check" do
      GitHub.flipper[:cap_filter_projects_dashboard].enable
      MemexProjectVisit.create({
        viewer_id: @org_member.id,
        memex_project_id: @memexes.first.id,
        last_visited_at: 2.days.ago,
        owner_id: @memexes.first.owner.id,
        owner_type: @memexes.first.owner.type
      })
      MemexProjectVisit.create({
        viewer_id: @org_member.id,
        memex_project_id: @memexes.second.id,
        last_visited_at: 1.day.ago,
        owner_id: @memexes.second.owner.id,
        owner_type: @memexes.second.owner.type
      })

      assert_equal [], @org.recently_visited_projects(viewer: @org_member, cap_filter: cap_unauthorizing_filter).map(&:title)
    end

    context "memex project status updates" do
      test "does not create N+1 queries" do
        memexes = [
          create(:memex_project, owner: @org, title: "abc", creator: @admin),
          create(:memex_project, owner: @org, title: "abcde", creator: @admin),
          create(:memex_project, owner: @org, title: "def", creator: @admin),
        ]

        memexes.each { |memex| create(:memex_project_status, memex_project: memex) }

        memexes.each_with_index do |memex, index|
          MemexProjectVisit.create({
            viewer_id: @org_member.id,
            memex_project_id: memex.id,
            last_visited_at: (index + 1).days.ago,
            owner_id: memex.owner.id,
            owner_type: memex.owner.type
          })
        end

        recently_visited_projects = @org.recently_visited_projects(viewer: @org_member, cap_filter: cap_authorizing_filter)

        assert_query_count_per_table({ memex_project_statuses: 1 }) do
          @org.recently_visited_projects(viewer: @org_member, cap_filter: cap_authorizing_filter).each do |memex|
            assert memex.latest_status_update
          end
        end
      end
    end
  end

  def assert_accessible_memexes_equal(expected, org, viewer, min_permission_level = "read")
    result = org.accessible_memexes_scope(org.memex_projects, viewer, min_permission_level, :enumeration)
    assert_equal expected, result.count

    result = org.accessible_memexes_scope(org.memex_projects, viewer, min_permission_level, :batching)
    assert_equal expected, result.count
  end
end

class MemexProjectsDependencyOrganizationWideProjectRoleTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @owner = create(:user)
    @org = create(:business_plus_organization, admin: @owner)

    @member = create(:user)
    @org.add_member(@member, action: :write)

    @memex = create(:memex_project, owner: @org, title: "My Memex Project")
    @memex_org_read_access = create(:memex_project, owner: @org, title: "My Memex Project")
    @memex_org_read_access.update_organization_wide_role("project_reader", @owner)

    @memex_org_write_access = create(:memex_project, owner: @org, title: "My Memex Project")
    @memex_org_write_access.update_organization_wide_role("project_writer", @owner)

    @memex_org_no_access = create(:memex_project, owner: @org, title: "My Memex Project")
    @memex_org_no_access.update_organization_wide_role("none", @owner)

    MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
  end

  context "#update_organization_wide_role" do
    test "sets the permission role for only projects that do not have a specific org permission role" do
      assert_nil ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")


      events = assert_performed_audit_entries(count: 1, only: "organization_wide_project_base_role.update") do
        @org.update_organization_wide_projects_role("project_reader", @owner)
      end

      expected_payload = {
        action: "organization_wide_project_base_role.update",
        old_project_base_role: "none",
        new_project_base_role: "project_reader",
        org_id: @org.id
      }

      assert_subset_hash expected_payload, events.first

      refute_nil ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")

      assert_equal "project_reader", ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value
      assert_equal ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value, @memex.organization_wide_role
      assert_equal "project_reader", @memex_org_read_access.organization_wide_role
      assert_equal "project_writer", @memex_org_write_access.organization_wide_role
      assert_equal "none", @memex_org_no_access.organization_wide_role

      new_memex_1 = create(:memex_project, owner: @org, title: "New Project 1")
      assert_equal ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value, new_memex_1.organization_wide_role

      events = assert_performed_audit_entries(count: 1, only: "organization_wide_project_base_role.update") do
        @org.update_organization_wide_projects_role("project_writer", @owner)
      end

      expected_payload = {
        action: "organization_wide_project_base_role.update",
        old_project_base_role: "project_reader",
        new_project_base_role: "project_writer",
        org_id: @org.id
      }

      assert_subset_hash expected_payload, events.first

      assert_equal "project_writer", ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value
      assert_equal ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value, @memex.organization_wide_role
      assert_equal "project_reader", ::Configuration::Entry.find_by(target_id: @memex_org_read_access.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value
      assert_equal "project_writer", ::Configuration::Entry.find_by(target_id: @memex_org_write_access.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value
      assert_equal "none", ::Configuration::Entry.find_by(target_id: @memex_org_no_access.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value

      new_memex_2 = create(:memex_project, owner: @org, title: "New Project 2")
      assert_equal ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value, new_memex_2.organization_wide_role

      @org.update_organization_wide_projects_role("project_admin", @owner)
      assert_equal "project_admin", ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value
      assert_equal ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value, @memex.organization_wide_role
      assert_equal "project_reader", ::Configuration::Entry.find_by(target_id: @memex_org_read_access.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value
      assert_equal "project_writer", ::Configuration::Entry.find_by(target_id: @memex_org_write_access.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value
      assert_equal "none", ::Configuration::Entry.find_by(target_id: @memex_org_no_access.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value
      new_memex_3 = create(:memex_project, owner: @org, title: "New Project 3")
      assert_equal ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value, new_memex_3.organization_wide_role

      @org.update_organization_wide_projects_role("none", @owner)
      assert_equal "none", ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value
      assert_equal ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value, @memex.organization_wide_role
      assert_equal "project_reader", ::Configuration::Entry.find_by(target_id: @memex_org_read_access.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value
      assert_equal "project_writer", ::Configuration::Entry.find_by(target_id: @memex_org_write_access.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value
      assert_equal "none", ::Configuration::Entry.find_by(target_id: @memex_org_no_access.id, target_type: "MemexProject", name: "memex_project_organization_wide_role")&.value

      new_memex_4 = create(:memex_project, owner: @org, title: "New Project 4")
      assert_equal ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")&.value, new_memex_4.organization_wide_role
    end

    test "throws unless updater is org admin" do
      assert_nil ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")

      assert_raises ArgumentError do
        @org.update_organization_wide_projects_role("project_admin", @member)
      end
    end

    test "setting invalid role name throws" do
      assert_raises_with_message(ArgumentError, "Invalid role name: test_test") do
        @org.update_organization_wide_projects_role("test_test", @owner)
      end
    end

    test "passes in the organization and business during instrumentation for enterprises" do
      admin  = create(:verified_user)
      org    = create(:enterprise_linked_organization, admin: admin)

      events = assert_performed_audit_entries(count: 1, only: "organization_wide_project_base_role.update") do
        org.update_organization_wide_projects_role("project_reader", admin)
      end

      expected_payload = {
        action: "organization_wide_project_base_role.update",
        old_project_base_role: "none",
        new_project_base_role: "project_reader",
        org_id: org.id,
        business_id: org.business.id,
      }

      assert_subset_hash expected_payload, events.first
    end
  end

  context "#projects_base_role" do
    test "permission role should default to global value if no org-wide base role is set" do
      assert_nil ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")
      assert_equal "project_writer", @org.projects_base_role
    end

    test "permission role should return correct role if org-wide base role is set" do
      assert_nil ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")
      assert_equal "project_writer", @org.projects_base_role

      @org.update_organization_wide_projects_role("none", @owner)
      refute_nil ::Configuration::Entry.find_by(target_id: @org.id, target_type: "User", name: "memex_project_organization_wide_role")
      assert_equal "none", @org.projects_base_role
    end

    test "permission role should return no access role if no global base role is set" do
      ::Configuration::Entry.destroy_all
      assert_nil ::Configuration::Entry.find_by(name: "memex_project_organization_wide_role")
      assert_equal "none", @org.projects_base_role
    end
  end

  context "#projects_without_base_role_set_count" do
    test "returns zero if no org projects" do
      empty_org = create(:business_plus_organization, admin: @owner)
      assert_equal 0, empty_org.projects_without_base_role_set_count
    end

    test "returns correct number of projects without a base role set" do
      assert_equal 1, @org.projects_without_base_role_set_count
    end
  end
end

if GitHub.spamminess_check_enabled?
  class MemexProjectsDependencyOrgSpammyUserTest < GitHub::TestCase
    include MemexHelpers

    fixtures do
      @admin = create(:verified_user)
      @org = create(:organization, admin: @admin)
      @org_member = create(:verified_user).tap { |u| @org.add_member(u) }
      @non_org_member = create(:verified_user)

      # Site admin viewer
      @site_admin_member = create(:staff_admin_user)
      @org.add_member(@site_admin_member)

      # Spammy user
      @spammy_user = create(:verified_user, spammy: true)
      @org.add_member(@spammy_user)

      @memexes = [
        create(:memex_project, owner: @org, title: "abc", creator: @admin),
        create(:memex_project, owner: @org, title: "abcde", creator: @admin),
        create(:memex_project, owner: @org, title: "def", creator: @admin),
        create(:memex_project, owner: @org, title: "defgh", creator: @admin, closed_at: 1.day.ago),
        create(:memex_project, owner: @org, title: "tuv", creator: @org_member),
        create(:memex_project, owner: @org, title: "wxyz", creator: @org_member, closed_at: 2.days.ago),
        create(:memex_project, owner: @org, title: nil, creator: @org_member, closed_at: 3.days.ago),
        create(:memex_project, owner: @org, title: "wxyz", creator: @org_member, deleted_at: 4.days.ago),
        create(:memex_project, owner: @org, title: "wxyz", creator: @org_member, deleted_at: 5.days.ago, closed_at: 6.days.ago),
      ]

      @spammy_project = create(:memex_project, owner: @org, title: "spam", creator: @spammy_user)
      @memexes << @spammy_project

      MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
    end

    context "#accessible_memexes_scope" do
      test "returns spammy memex project to spammy creator" do
        result = @org.accessible_memexes_scope(@org.memex_projects.active_projects, @spammy_user)
        assert_includes @org.memex_projects.pluck(:title), "spam"
        assert_equal 8, result.count
      end

      test "returns spammy memex project to site admin" do
        result = @org.accessible_memexes_scope(@org.memex_projects.active_projects, @site_admin_member)
        assert_includes @org.memex_projects.pluck(:title), "spam"
        assert_equal 8, result.count
      end
    end
  end

  class MemexProjectsDependencyOrgSpammyUserAccessTest < GitHub::TestCase
    include MemexHelpers

    fixtures do
      @admin = create(:verified_user)
      @org = create(:organization, admin: @admin)
      @org_member = create(:verified_user).tap { |u| @org.add_member(u) }
      @non_org_member = create(:verified_user)

      # Site admin viewer
      @site_admin_member = create(:staff_admin_user)
      @org.add_member(@site_admin_member)

      # Spammy user
      @spammy_user = create(:verified_user, spammy: true)
      @org.add_member(@spammy_user)

      @memexes = [
        create(:memex_project, owner: @org, title: "abc", creator: @admin),
        create(:memex_project, owner: @org, title: "abcde", creator: @admin),
        create(:memex_project, owner: @org, title: "def", creator: @admin),
        create(:memex_project, owner: @org, title: "defgh", creator: @admin, closed_at: 1.day.ago),
        create(:memex_project, owner: @org, title: "tuv", creator: @org_member),
        create(:memex_project, owner: @org, title: "wxyz", creator: @org_member, closed_at: 2.days.ago),
        create(:memex_project, owner: @org, title: nil, creator: @org_member, closed_at: 3.days.ago),
        create(:memex_project, owner: @org, title: "wxyz", creator: @org_member, deleted_at: 4.days.ago),
        create(:memex_project, owner: @org, title: "wxyz", creator: @org_member, deleted_at: 5.days.ago, closed_at: 6.days.ago),
      ]

      @spammy_project = create(:memex_project, owner: @org, title: "spam", creator: @spammy_user)
      @memexes << @spammy_project

      # Disable org wide access for all memexes
      @memexes.each do |memex|
        MemexHelpers::setup_organization_wide_access("none", memex)
      end

      @memexes[0].grant_role(@org_member, :reader)
      @memexes[1].grant_role(@org_member, :reader)

      @spammy_project.grant_role(@org_member, :reader)

      MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
    end

    test "does not return spammy projects that user has explicit access" do
      result = @org.accessible_memexes_scope(@org.memex_projects, @org_member)

      assert_predicate @spammy_project, :user_hidden?
      assert_same_elements [@memexes[0], @memexes[1]], result
    end
  end
end
