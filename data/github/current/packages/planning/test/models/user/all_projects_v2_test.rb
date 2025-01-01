# typed: true
# frozen_string_literal: true

require "test_helper"

# TODO
# Test for spammy user

class AllProjectsV2Test < GitHub::TestCase
  include DogstatsTestHelpers
  extend T::Sig

  fixtures do
    MemexHelpers.setup_organization_wide_access_for_projects("project_reader")

    @user_1 = create(:verified_user)
    @user_2 = create(:verified_user)
    @user_3 = create(:verified_user)

    @user_1_org = create(:organization, admin: @user_1)
    @user_2_org = create(:organization, admin: @user_2)
    @user_3_org = create(:organization, admin: @user_3)

    @user_3_org.add_member(@user_1)

    @user_1_memexes = [
      create(:memex_project, owner: @user_1, creator: @user_1),
      create(:memex_project, owner: @user_1, creator: @user_1, closed_at: 1.day.ago),
    ]

    @user_2_memexes = [
      create(:memex_project, :with_reader, reader: @user_1, owner: @user_2, creator: @user_2),
      create(:memex_project, :with_reader, reader: @user_1, owner: @user_2, creator: @user_2, closed_at: 1.day.ago),
    ]

    @user_1_org_memexes = [
      create(:memex_project, owner: @user_1_org, creator: @user_1),
      create(:memex_project, owner: @user_1_org, creator: @user_1, closed_at: 1.day.ago),
    ]

    @user_2_org_memexes = [
      create(:memex_project, owner: @user_2_org, creator: @user_2),
      create(:memex_project, owner: @user_2_org, creator: @user_2, closed_at: 1.day.ago),
    ]

    @user_3_org_memexes = [
      create(:memex_project, owner: @user_3_org, creator: @user_1),
      create(:memex_project, owner: @user_3_org, creator: @user_3),
      create(:memex_project, owner: @user_3_org, creator: @user_1, closed_at: 1.day.ago),
    ]
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    @user_1_accessible_memexes = {
      open: [
        @user_1_memexes[0],
        @user_2_memexes[0],
        @user_1_org_memexes[0],
        @user_3_org_memexes[0],
        @user_3_org_memexes[1]
      ],
      closed: [
        @user_1_memexes[1],
        @user_2_memexes[1],
        @user_1_org_memexes[1],
        @user_3_org_memexes[2]
      ]
    }
  end

  context "all results" do
    test "returns all the open memexes accessible to the user_1" do
      expected_memexes = @user_1_accessible_memexes[:open].flatten
      assert_same_elements expected_memexes, search(Search::Queries::MemexProjectQuery.new(""), @user_1)
    end
  end

  context "querying" do
    # We don't currently support `is:open,closed` or `is:open is:closed`
    # Omitting `is:` will default to `is:open`
    test "is:open|closed" do
      expected_open_memexes = @user_1_accessible_memexes[:open].flatten
      assert_same_elements expected_open_memexes, search(Search::Queries::MemexProjectQuery.new("is:open"), @user_1)

      expected_closed_memexes = @user_1_accessible_memexes[:closed].flatten
      assert_same_elements expected_closed_memexes, search(Search::Queries::MemexProjectQuery.new("is:closed"), @user_1)
    end

    test "creator:" do
      expected_memexes = @user_1_accessible_memexes[:open].flatten
        .filter { |memex| memex.creator == @user_2 }
      assert_same_elements expected_memexes,
        search(Search::Queries::MemexProjectQuery.new("creator:#{@user_2.login}"), @user_1)
    end

    test "is:template" do
      # Convert a handful of memexes into templates
      expected_memexes = [
        @user_1_memexes[0],
        @user_2_memexes[0],
        @user_1_org_memexes[0]
      ].flatten.tap do |memexes|
        memexes.map { |m| create(:memex_template, memex_project: m) }
      end

      assert_same_elements expected_memexes, search(Search::Queries::MemexProjectQuery.new("is:template"), @user_1)
    end

    test "sort" do
      expected_memexes = @user_1_accessible_memexes[:open].flatten.sort_by(&:title)
      assert_equal expected_memexes, search(Search::Queries::MemexProjectQuery.new("sort:title-asc"), @user_1)
    end

    test "composite search" do
      expected_memexes = @user_1_accessible_memexes[:closed].flatten
        .filter { |memex| memex.creator == @user_2 }
        .sort_by(&:created_at)
        .reverse
      assert_same_elements expected_memexes,
        search(Search::Queries::MemexProjectQuery.new("creator:#{@user_2.login} is:closed sort:created-desc"), @user_1)
    end
  end

  context "datadog stats" do
    test "stats once" do
      @user_1.all_projects_v2_for_user(query: Search::Queries::MemexProjectQuery.new(""), viewer: @user_1)

      assert_equal 1, GitHub.dogstats.timings("memex.all_projects.time").size
    end
  end

  private

  sig { params(query: Search::Queries::MemexProjectQuery, viewer: User).returns(T::Array[MemexProject]) }
  def search(query, viewer)
    T.must(viewer.all_projects_v2_for_user(query: query, viewer: viewer)).memex_projects
  end
end
