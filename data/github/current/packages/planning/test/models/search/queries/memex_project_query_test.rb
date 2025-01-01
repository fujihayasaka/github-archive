# typed: true
# frozen_string_literal: true

require "test_helper"

class SearchQueriesMemexProjectQueryTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  context "DEFAULT_QUERY" do
    test "returns open filter without a viewer" do
      assert_equal "is:open", Search::Queries::MemexProjectQuery::DEFAULT_QUERY
    end
  end

  context "#state_filters" do
    test "returns the value of active state filter" do
      assert_includes Search::Queries::MemexProjectQuery.new("is:Closed").state_filters, "closed"
    end

    test "can detect template searches" do
      assert_includes Search::Queries::MemexProjectQuery.new("is:template").state_filters, "template"
    end

    test "can detect private searches" do
      assert_includes Search::Queries::MemexProjectQuery.new("is:private").state_filters, "private"
    end

    test "can detect public searches" do
      assert_includes Search::Queries::MemexProjectQuery.new("is:public").state_filters, "public"
    end

    test "returns nil if there is no active state filter" do
      assert_equal [], Search::Queries::MemexProjectQuery.new("creator:#{@user}").state_filters
    end
  end

  context "#default_open_filter?" do
    test "returns true if the query only has an open filter" do
      assert_predicate Search::Queries::MemexProjectQuery.new("is:open"), :default_open_filter?
    end

    test "returns false if the query does not have an open filter" do
      refute_predicate Search::Queries::MemexProjectQuery.new("is:closed"), :default_open_filter?
    end

    test "returns false if the query has other filters" do
      refute_predicate Search::Queries::MemexProjectQuery.new("is:open is:template"), :default_open_filter?
    end

    context "strip_template_filter" do
      test "returns true if the query only has open and template filters" do
        assert Search::Queries::MemexProjectQuery.new("is:open is:template").default_open_filter?(strip_template_filter: true)
      end

      test "returns false if the query does not have an open filter" do
        refute Search::Queries::MemexProjectQuery.new("is:template").default_open_filter?(strip_template_filter: true)
      end

      test "returns false if the query has other filters" do
        refute Search::Queries::MemexProjectQuery.new("is:open is:public is:template").default_open_filter?(strip_template_filter: true)
      end
    end
  end

  context "#default_closed_filter?" do
    test "returns true if the query only has a closed filter" do
      assert_predicate Search::Queries::MemexProjectQuery.new("is:closed"), :default_closed_filter?
    end

    test "returns false if the query does not have a closed filter" do
      refute_predicate Search::Queries::MemexProjectQuery.new("is:open"), :default_closed_filter?
    end

    test "returns false if the query has other filters" do
      refute_predicate Search::Queries::MemexProjectQuery.new("is:closed is:template"), :default_closed_filter?
    end

    context "strip_template_filter" do
      test "returns true if the query only has closed and template filters" do
        assert Search::Queries::MemexProjectQuery.new("is:closed is:template").default_closed_filter?(strip_template_filter: true)
      end

      test "returns false if the query does not have a closed filter" do
        refute Search::Queries::MemexProjectQuery.new("is:template").default_closed_filter?(strip_template_filter: true)
      end

      test "returns false if the query has other filters" do
        refute Search::Queries::MemexProjectQuery.new("is:closed is:public is:template").default_closed_filter?(strip_template_filter: true)
      end
    end
  end

  context "#has_template_filter?" do
    test "returns true if the query has a template filter" do
      assert_predicate Search::Queries::MemexProjectQuery.new("is:open is:template"), :has_template_filter?
    end

    test "returns false if the query does not have a template filter" do
      refute_predicate Search::Queries::MemexProjectQuery.new("is:open"), :has_template_filter?
    end
  end

  context "#only_template_filter?" do
    test "returns true if the query only has a template filter" do
      assert_predicate Search::Queries::MemexProjectQuery.new("is:template"), :only_template_filter?
    end

    test "returns false if the query does not have a template filter" do
      refute_predicate Search::Queries::MemexProjectQuery.new("is:open"), :only_template_filter?
    end

    test "returns false if the query has other filters" do
      refute_predicate Search::Queries::MemexProjectQuery.new("is:template is:public"), :only_template_filter?
    end
  end

  context "#creator_filter" do
    test "returns the value of the active creator filter" do
      assert_includes Search::Queries::MemexProjectQuery.new("creator:lerebear").creator_filter, "lerebear"
    end

    test "supports author as an alias for creator" do
      assert_includes Search::Queries::MemexProjectQuery.new("author:lerebear").creator_filter, "lerebear"
    end

    test "returns if there is no active creator filter" do
      assert_empty Search::Queries::MemexProjectQuery.new("is:open").creator_filter
    end
  end

  context "#non_default_query?" do
    test "returns true if the modeled query is not the default one" do
      assert Search::Queries::MemexProjectQuery.new("is:open creator:#{@user}").non_default_query?
    end

    test "returns false if the modeled query is nil" do
      refute Search::Queries::MemexProjectQuery.new(nil).non_default_query?
    end

    test "returns false if the modeled query is the default one" do
      refute Search::Queries::MemexProjectQuery.new("is:open").non_default_query?
    end
  end

  context "#stringify" do
    test "removes duplicates filters and preserves order" do
      assert_equal(
        "is:open is:closed creator:lerebear creator:probablylerebear",
        Search::Queries::MemexProjectQuery
          .new("is:open is:closed creator:lerebear creator:probablylerebear creator:lerebear")
          .stringify
      )
    end

    test "orders filters before free text terms" do
      assert_equal "is:open foo bar", Search::Queries::MemexProjectQuery.new("foo is:open bar").stringify
    end
  end

  context "#sort_filter" do
    test "returns the value of the sort filter" do
      assert_equal(%w[title asc], Search::Queries::MemexProjectQuery.new("sort:title-asc").sort_filter)
      assert_equal(%w[updated_at asc], Search::Queries::MemexProjectQuery.new("sort:updated-asc").sort_filter)
      assert_equal(%w[updated_at desc], Search::Queries::MemexProjectQuery.new("sort:updated-desc").sort_filter)
      assert_equal(%w[created_at asc], Search::Queries::MemexProjectQuery.new("sort:created-asc").sort_filter)
      assert_equal(%w[created_at desc], Search::Queries::MemexProjectQuery.new("sort:created-desc").sort_filter)
    end

    test "returns the default value of the sort filter when none is given" do
      assert_equal(%w[updated_at desc], Search::Queries::MemexProjectQuery.new("").sort_filter)
    end
  end

  context "#memex_project_query" do
    test "creates a new query with replaced values" do
      query = Search::Queries::MemexProjectQuery.new("")
      is_opened_query = query.memex_project_query(replace: { is: "opened" })
      assert_equal "is:opened", is_opened_query.stringify
      assert_equal "", query.stringify
    end
  end

  context "#selected_projects_sort?" do
    test "should return true if the sort is selected" do
      assert Search::Queries::MemexProjectQuery.new("sort:title-asc").selected_projects_sort?("title-asc")
    end

    test "should return true for the default sort if no sort is explicitly set" do
      assert Search::Queries::MemexProjectQuery.new("").selected_projects_sort?(MemexesHelper::DEFAULT_SORT)
    end

    test "should return false if the sort is not selected" do
      refute Search::Queries::MemexProjectQuery.new("sort:title-asc").selected_projects_sort?("created-asc")
    end
  end

  context "#valid_sort?" do
    test "should return true if the sort is valid" do
      query = Search::Queries::MemexProjectQuery.new("")

      MemexesHelper::SORTS.each do |_key, value|
        assert query.valid_sort?(value)
      end

      refute query.valid_sort?("fake-sort")
    end
  end

  context "single_term_query" do
    test "uses the full query if no state filters are present" do
      query = Search::Queries::MemexProjectQuery.new("foo bar")
      assert_equal "foo bar", query.single_term_query
    end

    test "removes excess whitespace between words" do
      query = Search::Queries::MemexProjectQuery.new("foo     bar")
      assert_equal "foo bar", query.single_term_query
    end

    test "sets the single term query to the full value of the query after any state filters" do
      query = Search::Queries::MemexProjectQuery.new("is:template is:open foo bar")
      assert_equal "foo bar", query.single_term_query
    end

    test "sets the single term query to the full value of the query before any state filters" do
      query = Search::Queries::MemexProjectQuery.new("foo bar is:template is:open")
      assert_equal "foo bar", query.single_term_query
    end

    test "uses the rightmost part of the query if is interrupted by state filters" do
      query = Search::Queries::MemexProjectQuery.new("foo is:template is:open bar")
      assert_equal "bar", query.single_term_query
    end
  end
end
