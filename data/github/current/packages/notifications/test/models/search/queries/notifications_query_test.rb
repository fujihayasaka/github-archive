# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesNotificationsQueryTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    enable_feature_flag(:issues_react_inbox_tabs, @user)
  end

  def create_query(query)
    Search::Queries::NotificationsQuery.new(query: query, viewer: @user)
  end

  context "#contains_unsupported_qualifiers?" do
    test "is true if query contains qualifiers not supported by mysql" do
      assert_predicate create_query("is:read some free text"), :contains_unsupported_qualifiers?
    end

    test "is false if query contains qualifiers supported by mysql" do
      refute_predicate create_query("is:read"), :contains_unsupported_qualifiers?
      refute_predicate create_query("is:discussion"), :contains_unsupported_qualifiers?
      refute_predicate create_query("reason:mention"), :contains_unsupported_qualifiers?
      refute_predicate create_query("repo:github/github"), :contains_unsupported_qualifiers?
      refute_predicate create_query("org:latentflip"), :contains_unsupported_qualifiers?
      refute_predicate create_query("author:latentflip"), :contains_unsupported_qualifiers?
      refute_predicate create_query("is:read author:latentflip"), :contains_unsupported_qualifiers?
    end
  end

  context "#supported_by_mysql?" do
    test "is true if query contains query supported by mysql" do
      assert_predicate create_query("is:read"), :supported_by_mysql?
      assert_predicate create_query("is:discussion"), :supported_by_mysql?
      assert_predicate create_query("reason:mention"), :supported_by_mysql?
      assert_predicate create_query("repo:github/github"), :supported_by_mysql?
      assert_predicate create_query("author:latentflip"), :supported_by_mysql?
      assert_predicate create_query("is:read author:latentflip"), :supported_by_mysql?
      assert_predicate create_query("org:latentflip"), :supported_by_mysql?
    end

    test "is false if is: qualifier is pr or issue" do
      refute_predicate create_query("is:issue"), :supported_by_mysql?
      refute_predicate create_query("is:pr"), :supported_by_mysql?
      refute_predicate create_query("is:pull-request"), :supported_by_mysql?
    end

    test "is false if query contains qualifiers not supported by mysql" do
      refute_predicate create_query("is:read some free text"), :supported_by_mysql?
    end
  end

  context "#stringify" do
    test "includes the specified statuses" do
      assert_equal "stuff is:read", create_query("stuff").stringify(read: true)
      assert_equal "stuff is:unread", create_query("stuff").stringify(unread: true)
      assert_equal "stuff is:done", create_query("stuff").stringify(archived: true)
      assert_equal "stuff is:saved", create_query("stuff").stringify(starred: true)

      assert_equal "stuff", create_query("stuff is:read").stringify(read: false)
      assert_equal "stuff", create_query("stuff is:unread").stringify(unread: false)
      assert_equal "stuff", create_query("stuff is:done").stringify(archived: false)
      assert_equal "stuff", create_query("stuff is:saved").stringify(starred: false)
    end

    test "includes the specified reasons" do
      assert_equal "stuff reason:mention reason:assign", create_query("stuff reason:author").stringify(reasons: %w[mention assign])
    end

    test "strips is:read and is:unread if both are present" do
      assert_equal(
        "stuff",
        create_query("stuff is:read is:unread").stringify(read: true, unread: true),
      )
    end

    test "does not strip is:read and is:unread if done is also present" do
      query = create_query("stuff is:read is:unread is:done")

      assert_equal(
        "stuff is:read is:unread is:done",
        query.stringify(read: true, unread: true, archived: true),
      )
    end
  end

  context "#unread?" do
    test "uses the is:unread qualifier from the raw query" do
      refute_predicate create_query("other stuff is:bad"), :unread?
      assert_predicate create_query("other stuff is:unread"), :unread?
    end
  end

  context "#read?" do
    test "uses the is:read qualifier from the raw query" do
      refute_predicate create_query("other stuff is:bad"), :read?
      assert_predicate create_query("other stuff is:read"), :read?
    end
  end

  context "#archived?" do
    test "uses the is:done qualifier from the raw query" do
      refute_predicate create_query("other stuff is:bad"), :archived?
      assert_predicate create_query("other stuff is:done"), :archived?
    end
  end

  context "#starred?" do
    test "uses the is:saved qualifier from the raw query" do
      refute_predicate create_query("other stuff is:bad"), :starred?
      assert_predicate create_query("other stuff is:saved"), :starred?
    end
  end

  context "#reasons" do
    test "only includes valid reason values" do
      assert_equal ["mention"], create_query("hello reason:mention").reasons
      assert_equal [], create_query("reason:bad").reasons
      assert_equal ["assign"], create_query("reason:ASSIGn").reasons
      assert_equal Newsies::NotificationEntry::PARTICIPATING_REASONS, create_query("reason:participating").reasons
    end

    test "handles hyphenated reasons" do
      assert_equal ["review_requested"], create_query("hello reason:review-requested").reasons
    end
  end

  context "participating?" do
    test "returns true if any reason is participating" do
      refute_predicate create_query("stuff reason:assign"), :participating?
      assert_predicate create_query("other reason:participating reason:bad"), :participating?
      assert_predicate create_query("other reason:participating reason:mention"), :participating?
    end
  end

  context "#is_only_an_inbox_query?" do
    test "returns false if the query is for saved notifications" do
      refute_predicate create_query("is:saved"), :is_only_an_inbox_query?
    end

    test "returns false if the query is for done notifications" do
      refute_predicate create_query("is:done"), :is_only_an_inbox_query?
    end

    test "returns false if the query includes a reason" do
      refute_predicate create_query("reason:participating"), :is_only_an_inbox_query?
    end

    test "returns true for a blank query" do
      assert_predicate create_query(""), :is_only_an_inbox_query?
    end

    test "returns true for an unread only query" do
      assert_predicate create_query("is:unread"), :is_only_an_inbox_query?
    end

    test "returns true for read and unread notifications query" do
      assert_predicate create_query("is:unread is:read"), :is_only_an_inbox_query?
      assert_predicate create_query("is:read is:unread"), :is_only_an_inbox_query?
    end

    test "returns false for non-blank query that further filters the inbox" do
      refute_predicate create_query("is:issue stuff"), :is_only_an_inbox_query?
    end
  end

  context "#statuses" do
    test "defaults to read and unread" do
      assert_same_elements %w[unread read], create_query("").statuses
    end

    test "includes read for is:read" do
      assert_same_elements ["read"], create_query("is:read").statuses
    end

    test "includes unread for is:unread" do
      assert_same_elements ["unread"], create_query("is:unread").statuses
    end

    test "includes archived for is:done" do
      assert_same_elements ["archived"], create_query("is:done").statuses
    end

    test "supports multiple statuses" do
      assert_same_elements %w[archived read unread], create_query("is:read is:unread is:done").statuses
    end
  end

  context "#repositories" do
    test "only includes repositories that exist" do
      repo = create(:repository)
      assert_equal [], create_query("hello repo:not/a-repo").repositories
      assert_equal [repo], create_query("repo:#{repo.name_with_owner}").repositories
    end

    test "only includes repositories readable by the viewer" do
      owned_repo = create(:private_repository, owner: @user)
      private_repo = create(:private_repository)
      assert_equal [owned_repo], create_query("repo:#{owned_repo.name_with_owner}").repositories
      assert_equal [], create_query("repo:#{private_repo.name_with_owner}").repositories
    end
  end

  context "#thread_types" do
    test "returns SecurityAdvisory and RepositoryDependabotAlertsThread threads in addition to RepositoryVulnerabilityAlert" do
      query = create_query("is:repository-vulnerability-alert")
      assert_predicate query, :supported_by_mysql?
      assert_equal %w[RepositoryVulnerabilityAlert RepositoryDependabotAlertsThread SecurityAdvisory], query.thread_types
    end
  end

  context "#focusing?" do
    test "does include view focusing in the query" do
      refute create_query("other is:read").focusing?
    end

    test "includes view focusing in the query" do
      assert create_query("other view:focusing is:read").focusing?
    end
  end

  context "#team_mention?" do
    test "does include view team_mention in the query" do
      refute create_query("other is:read").team_mention?
    end

    test "includes view team_mention in the query" do
      assert create_query("other view:team_mention is:read").team_mention?
    end
  end

  context "#not_focus_team_mentioned?" do
    test "does include view not_focus_team_mention in the query" do
      refute create_query("other is:read").not_focus_team_mentioned?
    end

    test "includes view not_focus_team_mention in the query" do
      assert create_query("other view:not_focus_team_mention is:read").not_focus_team_mentioned?
    end
  end

  context "#client_apps_important?" do
    test "does not include view client_apps_important in the query" do
      refute create_query("other is:read").client_apps_important?
    end

    test "includes view client_apps_important in the query" do
      assert create_query("other view:client_apps_important is:read").client_apps_important?
    end
  end

  context "#mixed_focus_team_mentioned?" do
    test "view order: focus > team_mention > other" do
      query_rtl = create_query("other view:not_focus_team_mention view:team_mention view:focusing is:read")
      query_ltr = create_query("other view:focusing view:team_mention view:not_focus_team_mention is:read")

      assert query_rtl.focusing?
      assert query_ltr.focusing?

      refute query_rtl.team_mention?
      refute query_ltr.team_mention?

      refute query_rtl.not_focus_team_mentioned?
      refute query_ltr.not_focus_team_mentioned?
    end
  end
end
