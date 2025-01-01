# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectsDependencyUserTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
    @other_user = create(:verified_user)

    @memexes = [
      create(:memex_project, owner: @user, title: "abc", creator: @user),
      create(:memex_project, owner: @user, title: "abcde", creator: @user),
      create(:memex_project, owner: @user, title: "def", creator: @user),
      create(:memex_project, owner: @user, title: "defgh", creator: @user, closed_at: 1.day.ago),
      create(:memex_project, owner: @user, title: "tuv", creator: @user),
      create(:memex_project, owner: @user, title: "wxyz", creator: @user, closed_at: 2.days.ago),
      create(:memex_project, owner: @user, title: nil, creator: @user, closed_at: 3.days.ago),
      create(:memex_project, owner: @user, title: "wxyz", creator: @user, deleted_at: 4.days.ago),
      create(:memex_project, owner: @user, title: "abc", creator: @user, deleted_at: 5.days.ago, closed_at: 6.days.ago),
    ]

    # Spammy user
    @spammy_user = create(:verified_user, spammy: true)
    @spammy_user.emails.first.verify!

    @spammy_memexes = [
      create(:memex_project, owner: @spammy_user, title: "spam-abc", creator: @spammy_user),
      create(:memex_project, owner: @spammy_user, title: "spam-abcde", creator: @spammy_user),
      create(:memex_project, owner: @spammy_user, title: "spam-def", creator: @spammy_user),
      create(:memex_project, owner: @spammy_user, title: "spam-defgh", creator: @spammy_user, closed_at: 1.day.ago),
      create(:memex_project, owner: @spammy_user, title: "spam-tuv", creator: @spammy_user),
      create(:memex_project, owner: @spammy_user, title: "spam-wxyz", creator: @spammy_user, closed_at: 2.days.ago),
      create(:memex_project, owner: @spammy_user, title: nil, creator: @spammy_user, closed_at: 3.days.ago),
      create(:memex_project, owner: @user, title: nil, creator: @user, deleted_at: 4.days.ago),
      create(:memex_project, owner: @user, title: nil, creator: @user, deleted_at: 5.days.ago, closed_at: 6.days.ago),
    ]
  end

  context "#user_projects_enabled?" do
    test "returns true by default (for non emu users)" do
      assert @user.user_projects_enabled?
    end

    test "returns true for EMU users on a full Enterprise plan", skip_enterprise: true do
      business = create :business, :enterprise_managed
      emu = create :emu, business: business
      assert emu.user_projects_enabled?
    end

    test "returns false for EMU users on a basic Copilot Standalone Enterprise plan", skip_enterprise: true do
      business = create :business, :enterprise_managed
      business.update(seats_plan_type: :basic)
      emu = create :emu, business: business
      refute emu.user_projects_enabled?
    end
  end

  context "#can_be_added_to_memex_project?" do
    test "returns false when no project owner is given" do
      refute @user.can_be_added_to_memex_project?(memex_owner: nil, viewer: @other_user)
    end

    test "returns false when the user is the viewer" do
      refute @user.can_be_added_to_memex_project?(memex_owner: @other_user, viewer: @user)

      org = create(:organization, admin: @user)
      refute @user.can_be_added_to_memex_project?(memex_owner: org, viewer: @user)
    end

    test "returns true for a user project owner when the user being added is not the viewer" do
      assert @user.can_be_added_to_memex_project?(memex_owner: @other_user, viewer: @other_user)
    end

    test "returns true for an org project owner when the user being added is not the viewer and belongs to the org" do
      org = create(:organization, admin: @other_user)
      org.add_member(@user)
      assert @user.can_be_added_to_memex_project?(memex_owner: org, viewer: @other_user)
    end

    test "returns false for an org project owner when the user being added does not belong to the org" do
      org = create(:organization, admin: @other_user)
      refute @user.can_be_added_to_memex_project?(memex_owner: org, viewer: @other_user)
    end

    test "returns false when the user being added has been blocked by the viewer" do
      @other_user.block(@user)

      refute @user.can_be_added_to_memex_project?(memex_owner: @other_user, viewer: @other_user)

      org = create(:organization, admin: @other_user)
      org.add_member(@user)
      refute @user.can_be_added_to_memex_project?(memex_owner: org, viewer: @other_user)
    end

    test "returns false when the user being added has blocked the viewer" do
      @user.block(@other_user)

      refute @user.can_be_added_to_memex_project?(memex_owner: @other_user, viewer: @other_user)

      org = create(:organization, admin: @other_user)
      org.add_member(@user)
      refute @user.can_be_added_to_memex_project?(memex_owner: org, viewer: @other_user)
    end

    test "can be efficiently loaded for many users at once for a user Memex owner" do
      viewer = @user
      memex_owner = viewer
      user1 = @other_user
      user2, user3 = create_pair(:user)
      users = [user1, user2, user3]

      user1.block viewer
      viewer.block user3

      assert_query_count(1) do
        GitHub::PrefillAssociations.prefill_batch_method(users, :can_be_added_to_memex_project?, {
          memex_owner: memex_owner,
          viewer: viewer,
        })
      end

      assert_query_count(0) do
        refute user1.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer)
        assert user2.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer)
        refute user3.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer)
      end
    end

    test "can be efficiently loaded for many users at once for an organization Memex owner" do
      viewer = @user
      memex_owner = create(:organization, plan: "business_plus", seats: 10, admin: viewer)
      repo = create(:private_repository, owner: memex_owner)
      user1 = @other_user
      user2, user3, user4 = create_list(:user, 3)
      users = [user1, user2, user3, user4]

      user1.block viewer
      viewer.block user3
      memex_owner.add_member(user2) # org member
      repo.add_member(user4) # outside collaborator

      assert_query_count(5) do
        GitHub::PrefillAssociations.prefill_batch_method(users, :can_be_added_to_memex_project?, {
          memex_owner: memex_owner,
          viewer: viewer,
        })
      end

      assert_query_count(0) do
        refute user1.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer)
        assert user2.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer)
        refute user3.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer)
        assert user4.can_be_added_to_memex_project?(memex_owner: memex_owner, viewer: viewer)
      end
    end
  end

  context "#search_memex_projects" do
    test "returns a page of results for open memexes by default (for a blank query)" do
      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new(""),
        viewer: @user
      )
      assert_equal %w[tuv def abcde abc], result.memex_projects.map(&:title)
    end

    if GitHub.spamminess_check_enabled?
      test "returns spammy results when the viewer is the creator" do
        result = @spammy_user.search_memex_projects(
          query: Search::Queries::MemexProjectQuery.new(""),
          viewer: @spammy_user
        )
        assert_equal %w[spam-tuv spam-def spam-abcde spam-abc], result.memex_projects.map(&:title)
      end
    end

    test "returns no results when the viewer is another user" do
      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new(""),
        viewer: @other_user
      )
      assert_equal [], result.memex_projects.map(&:title)
    end

    test "applies a state filter when it is present in the query" do
      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:closed"),
        viewer: @user
      )
      assert_equal [nil, "wxyz", "defgh"], result.memex_projects.map(&:title)
    end

    test "applies a creator filter when it is present in the query" do
      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("creator:#{@user}"),
        viewer: @user
      )
      assert_equal %w[tuv def abcde abc], result.memex_projects.map(&:title)
    end

    test "supports @me macro in the creator filter" do
      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:open creator:@me"),
        viewer: @user
      )
      assert_equal %w[tuv def abcde abc], result.memex_projects.map(&:title)
    end

    test "supports @me macro in the creator filter without viewer" do
      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:open creator:@me"),
        viewer: nil,
      )
      assert_equal [], result.memex_projects
    end

    test "applies a full-text search when it is present in the query" do
      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:open de"),
        viewer: @user
      )
      assert_equal %w[def abcde], result.memex_projects.map(&:title)

      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:closed de"),
        viewer: @user
      )
      assert_equal ["defgh"], result.memex_projects.map(&:title)
    end

    test "supports full-text search against the default memex title for untitled memexes" do
      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("is:closed #{MemexProject::DEFAULT_TITLE}"),
        viewer: @user
      )
      assert_equal [@memexes[6].number], result.memex_projects.map(&:number)
    end

    test "returns a correct page metadata" do
      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("creator:#{@user} de"),
        viewer: @user,
        cursor: @memexes.third.number,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal @memexes.second.number, result.next_page_cursor
      assert_equal 2, result.total_open_count
      assert_equal 0, result.total_closed_count
    end

    test "returns correct data for created_at queries" do
      user = create(:verified_user)

      memexes = [
        create(:memex_project, owner: user, title: "abc", creator: user, created_at: 1.day.ago),
        create(:memex_project, owner: user, title: "abc", creator: user, created_at: 2.days.ago),
        create(:memex_project, owner: user, title: "abc", creator: user, created_at: 3.days.ago),
        create(:memex_project, owner: user, title: "abc", creator: user, created_at: 4.days.ago),
      ]

      result = user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:created-desc"),
        viewer: user,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.second.number, result.next_page_cursor
      assert_equal 4, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:created-desc"),
        viewer: user,
        cursor: memexes.second.number,
        sort_query_cursor: memexes.second.created_at.to_s,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.third.number, result.next_page_cursor
      assert_equal 3, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:created-asc"),
        viewer: user,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.third.number, result.next_page_cursor
      assert_equal 4, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:created-asc"),
        viewer: user,
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
      user = create(:verified_user)
      memexes = 4.times.map do |n|
        Timecop.freeze(n.days.ago) do
          create(:memex_project, owner: user, title: "abc-#{n + 1}")
        end
      end

      result = user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:updated-desc"),
        viewer: user,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.second.number, result.next_page_cursor
      assert_equal 4, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:updated-desc"),
        viewer: user,
        cursor: memexes.second.number,
        sort_query_cursor: memexes.second.updated_at.to_s,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.third.number, result.next_page_cursor
      assert_equal 3, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:updated-asc"),
        viewer: user,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal memexes.third.number, result.next_page_cursor
      assert_equal 4, result.total_open_count
      assert_equal 0, result.total_closed_count

      result = user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("sort:updated-asc"),
        viewer: user,
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
      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("creator:#{@user} de sort:title-asc"),
        viewer: @user,
        limit: 1
      )

      assert_predicate result, :has_next_page?
      assert_equal @memexes.third.number, result.next_page_cursor
      assert_equal @memexes.third.title, result.sort_query_cursor
      assert_equal 2, result.total_open_count
      assert_equal 1, result.total_closed_count

      result = @user.search_memex_projects(
        query: Search::Queries::MemexProjectQuery.new("creator:#{@user} de sort:title-asc"),
        viewer: @user,
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

  context "#accessible_memexes_scope" do
    test "returns all active memex projects for the owner" do
      result = @user.accessible_memexes_scope(@user.memex_projects, @user)
      assert_equal 7, result.count
    end

    test "returns no memex projects for another viewer" do
      result = @user.accessible_memexes_scope(@user.memex_projects, @other_user)
      assert_equal 0, result.count
    end

    if GitHub.spamminess_check_enabled?
      test "does not return spammy projects to collaborator" do
        collaborator = create(:verified_user)

        memex = create(:memex_project, :with_reader, reader: collaborator, owner: @spammy_user, creator: @spammy_user, title: "spammy project")
        assert_predicate memex, :user_hidden?

        result = @spammy_user.accessible_memexes_scope(@spammy_user.memex_projects, collaborator, "read")
        assert_empty result
      end

      test "does not return spammy public projects for another viewer" do
        create(:memex_project, owner: @spammy_user, title: "abcde", creator: @spammy_user, public: true)

        result = @spammy_user.accessible_memexes_scope(@spammy_user.memex_projects, @other_user)
        assert_equal 0, result.count
      end
    end

    test "does not return public projects for another viewer if write permissions are requested" do
      create(:memex_project, owner: @user, title: "abcde", public: true)

      result = @user.accessible_memexes_scope(@user.memex_projects, @other_user, "write")
      assert_equal 0, result.count
    end

    test "return public projects for another viewer if read permissions are requested" do
      create(:memex_project, owner: @user, title: "abcde", public: true)

      result = @user.accessible_memexes_scope(@user.memex_projects, @other_user, "read")
      assert_equal 1, result.count
    end

    test "does return projects for collaborator with read access with read permissions" do
      owner = create(:verified_user)
      collaborator = create(:verified_user)

      memex = create(:memex_project, :with_reader, reader: collaborator, owner: owner, title: "abcde")

      result = owner.accessible_memexes_scope(owner.memex_projects, collaborator, "read")
      assert_equal [memex], result
    end

    test "does not return projects for collaborator with write access with read permissions" do
      owner = create(:verified_user)
      collaborator = create(:verified_user)

      memex = create(:memex_project, :with_reader, reader: collaborator, owner: owner, title: "abcde")

      result = owner.accessible_memexes_scope(owner.memex_projects, collaborator, "write")
      assert_equal 0, result.count
    end

    test "does return projects for collaborator with write access with write permissions" do
      owner = create(:verified_user)
      collaborator = create(:verified_user)

      memex = create(:memex_project, :with_writer, writer: collaborator, owner: owner, title: "abcde")

      result = owner.accessible_memexes_scope(owner.memex_projects, collaborator, "write")
      assert_equal [memex], result
    end
  end

  test" #memex_column_hash returns expected values" do
    column_hash = @user.memex_column_hash
    expected_column_hash = {
      avatarUrl: @user.primary_avatar_url(40),
      id: @user.id,
      login: @user.login,
      url: @user.permalink,
    }
    assert_same_hash expected_column_hash, column_hash
  end

  test "#memex_suggestion_hash returns expected values" do
    suggestion_hash = @user.memex_suggestion_hash(selected: true)
    expected_suggestion_hash = {
      avatarUrl: @user.primary_avatar_url(40),
      id: @user.id,
      login: @user.login,
      name: @user.profile_name,
      selected: true,
      url: @user.permalink,
    }
    assert_same_hash expected_suggestion_hash, suggestion_hash
  end

  test "#memex_reviewer_hash returns expected values" do
    reviewer_hash = @user.memex_reviewer_hash
    expected_reviewer_hash = {
      avatarUrl: @user.primary_avatar_url(40),
      id: @user.id,
      login: @user.login,
      name: @user.name,
      url: @user.permalink,
      type: "User",
    }
    assert_same_hash expected_reviewer_hash, reviewer_hash
  end
end
