# typed: true
# frozen_string_literal: true

require "test_helper"

class SponsorsExploreFilterSetTest < GitHub::TestCase
  context ".hydro_ecosystem_filter_option_for" do
    test "returns :ECOSYSTEM_UNKNOWN for an unknown value" do
      assert_equal :ECOSYSTEM_UNKNOWN, SponsorsExploreFilterSet
        .hydro_ecosystem_filter_option_for(value: "invalid", label: "")
    end

    test "handles all ecosystems at once" do
      assert_equal :ECOSYSTEM_ALL, SponsorsExploreFilterSet.hydro_ecosystem_filter_option_for(
        value: nil,
        label: SponsorsExploreFilterSet::ECOSYSTEM_NAMES[nil],
      )
    end

    test "handles Cargo/Rust ecosystem" do
      assert_equal :ECOSYSTEM_CARGO, SponsorsExploreFilterSet
        .hydro_ecosystem_filter_option_for(value: "RUST", label: SponsorsExploreFilterSet::ECOSYSTEM_NAMES["RUST"])
    end

    test "handles RubyGems ecosystem" do
      assert_equal :ECOSYSTEM_RUBYGEMS, SponsorsExploreFilterSet.hydro_ecosystem_filter_option_for(
        value: "RUBYGEMS",
        label: SponsorsExploreFilterSet::ECOSYSTEM_NAMES["RUBYGEMS"],
      )
    end

    test "handles Composer ecosystem" do
      assert_equal :ECOSYSTEM_COMPOSER, SponsorsExploreFilterSet.hydro_ecosystem_filter_option_for(
        value: "COMPOSER",
        label: SponsorsExploreFilterSet::ECOSYSTEM_NAMES["COMPOSER"],
      )
    end

    test "handles GitHub Actions ecosystem" do
      assert_equal :ECOSYSTEM_GITHUB_ACTIONS, SponsorsExploreFilterSet.hydro_ecosystem_filter_option_for(
        value: "ACTIONS",
        label: SponsorsExploreFilterSet::ECOSYSTEM_NAMES["ACTIONS"],
      )
    end

    test "handles Go ecosystem" do
      assert_equal :ECOSYSTEM_GO, SponsorsExploreFilterSet.hydro_ecosystem_filter_option_for(
        value: "GO",
        label: SponsorsExploreFilterSet::ECOSYSTEM_NAMES["GO"],
      )
    end

    test "handles Maven ecosystem" do
      assert_equal :ECOSYSTEM_MAVEN, SponsorsExploreFilterSet.hydro_ecosystem_filter_option_for(
        value: "MAVEN",
        label: SponsorsExploreFilterSet::ECOSYSTEM_NAMES["MAVEN"],
      )
    end

    test "handles npm ecosystem" do
      assert_equal :ECOSYSTEM_NPM, SponsorsExploreFilterSet.hydro_ecosystem_filter_option_for(
        value: "NPM",
        label: SponsorsExploreFilterSet::ECOSYSTEM_NAMES["NPM"],
      )
    end

    test "handles nuget ecosystem" do
      assert_equal :ECOSYSTEM_NUGET, SponsorsExploreFilterSet.hydro_ecosystem_filter_option_for(
        value: "NUGET",
        label: SponsorsExploreFilterSet::ECOSYSTEM_NAMES["NUGET"],
      )
    end

    test "handles pip ecosystem" do
      assert_equal :ECOSYSTEM_PIP, SponsorsExploreFilterSet.hydro_ecosystem_filter_option_for(
        value: "PIP",
        label: SponsorsExploreFilterSet::ECOSYSTEM_NAMES["PIP"],
      )
    end
  end

  context "#filtering?" do
    test "returns false when not overriding any filters" do
      filter_set = SponsorsExploreFilterSet.new
      refute_predicate filter_set, :filtering?
    end

    test "returns false when only overriding the sort order" do
      sort_by = "LEAST_USED"
      refute_equal SponsorsExploreFilterSet::DEFAULT_SORT_BY, sort_by, "need a non-default sort"
      filter_set = SponsorsExploreFilterSet.new(sort_by: sort_by)
      refute_predicate filter_set, :filtering?
    end

    test "returns false when only overriding whether to skip the cached result" do
      filter_set = SponsorsExploreFilterSet.new
      refute_predicate filter_set, :filtering?
    end

    test "returns true when overriding direct dependency default filter of true" do
      filter_set = SponsorsExploreFilterSet.new(direct_only: false)
      assert_predicate filter_set, :filtering?
    end

    test "returns false when only overriding the default page" do
      filter_set = SponsorsExploreFilterSet.new(page: 2)
      refute_predicate filter_set, :filtering?
    end

    test "returns false when only overriding the account" do
      filter_set = SponsorsExploreFilterSet.new(account_login: "foo")
      refute_predicate filter_set, :filtering?
    end
  end

  context "#with_default_filters" do
    test "returns a new filter set with the default filters, preserving sort and cache options as well as account" do
      sort_by = "LEAST_USED"
      refute_equal SponsorsExploreFilterSet::DEFAULT_SORT_BY, sort_by, "need a non-default sort"
      original_filter_set = SponsorsExploreFilterSet.new(
        account_login: "foo",
        page: 2,
        sort_by: sort_by,
        direct_only: false,
      )

      result = original_filter_set.with_default_filters

      assert_instance_of SponsorsExploreFilterSet, result
      assert_equal sort_by, result.sort_by, "should have kept original sort order"
      assert_equal 1, result.page, "should have reset the page"
      assert_equal "foo", result.account_login, "should have kept the original account filter"
      assert_predicate result, :direct_dependencies_only?, "should have reset the direct dependencies only filter"
    end
  end

  context "#no_results_explanation" do
    test "returns an explanation for all filters that limit the result set" do
      filter_set = SponsorsExploreFilterSet.new(ecosystems: ["NPM"], account_login: "foo")
      result = filter_set.no_results_explanation(account_is_viewer: true)
      assert_equal "You don't directly depend on any repositories in the npm ecosystem whose maintainers can be " \
        "sponsored.", result
    end

    test "handles several ecosystems" do
      filter_set = SponsorsExploreFilterSet.new(ecosystems: %w[NPM NUGET])
      assert_includes filter_set.no_results_explanation(account_is_viewer: false), " npm and nuget ecosystems "
    end

    test "handles a single ecosystem" do
      filter_set = SponsorsExploreFilterSet.new(ecosystems: ["ACTIONS"])
      assert_includes filter_set.no_results_explanation(account_is_viewer: false), " GitHub Actions ecosystem "
    end

    test "changes subject based on whether the account is the viewer" do
      filter_set = SponsorsExploreFilterSet.new(account_login: "foo")
      assert filter_set.no_results_explanation(account_is_viewer: true).start_with?("You don't ")
      assert filter_set.no_results_explanation(account_is_viewer: false).start_with?("foo does not ")
    end

    test "changes phrasing when direct and indirect dependencies are included" do
      filter_set = SponsorsExploreFilterSet.new(direct_only: false)
      assert filter_set.no_results_explanation(account_is_viewer: true).start_with?("You don't depend on")

      filter_set = SponsorsExploreFilterSet.new(direct_only: true)
      assert filter_set.no_results_explanation(account_is_viewer: true).start_with?("You don't directly depend on")
    end
  end

  context "#direct_dependencies_only?" do
    test "returns true when direct_only is truthy" do
      filter_set = SponsorsExploreFilterSet.new(direct_only: true)
      assert_predicate filter_set, :direct_dependencies_only?
    end

    test "returns true when direct_only is unspecified" do
      filter_set = SponsorsExploreFilterSet.new
      assert_predicate filter_set, :direct_dependencies_only?
    end

    test "returns false when direct_only is falsey" do
      filter_set = SponsorsExploreFilterSet.new(direct_only: nil)
      refute_predicate filter_set, :direct_dependencies_only?
    end
  end

  context "#query_args" do
    test "returns a hash of URL parameters to represent the current filters and sorting" do
      filter_set = SponsorsExploreFilterSet.new(
        direct_only: false,
        ecosystems: %w[NPM RUBYGEMS],
        account_login: "foo",
        page: 2,
        sort_by: SponsorsExploreLoader::LEAST_USED_SORT,
      )
      assert_equal({
        direct: "0",
        ecosystems: "NPM,RUBYGEMS",
        account: "foo",
        page: 2,
        sort_by: SponsorsExploreLoader::LEAST_USED_SORT,
      }, filter_set.query_args)
    end

    test "omits page URL parameter for first page" do
      filter_set = SponsorsExploreFilterSet.new(page: 1)
      assert_empty filter_set.query_args
    end

    test "uses 'ecosystem' param for a single ecosystem" do
      filter_set = SponsorsExploreFilterSet.new(ecosystems: ["NPM"])
      assert_equal({ ecosystem: "NPM" }, filter_set.query_args)
    end
  end

  context ".ecosystems_from" do
    test "returns ecosystem filters from URL parameters" do
      params = { ecosystems: "RUBYGEMS, Composer", ecosystem: " NPM" }
      assert_equal %w[RUBYGEMS Composer NPM], SponsorsExploreFilterSet.ecosystems_from(params)

      params = {}
      assert_equal [], SponsorsExploreFilterSet.ecosystems_from(params)

      params = { ecosystem: "maven" }
      assert_equal ["maven"], SponsorsExploreFilterSet.ecosystems_from(params)
    end
  end

  context "#ecosystems" do
    test "normalizes given ecosystems" do
      filter_set = SponsorsExploreFilterSet.new(ecosystems: ["npm", nil, "npm", "Maven"])
      assert_equal %w[MAVEN NPM], filter_set.ecosystems
    end
  end

  context "#eql?" do
    test "returns true when two filter sets produce the same URL parameters" do
      filter_set1 = SponsorsExploreFilterSet.new(ecosystems: ["RUBYGEMS"], account_login: "foo", direct_only: true)
      filter_set2 = SponsorsExploreFilterSet.new(ecosystems: %w[RUBYGEMS RUBYGEMS], account_login: "foo",
        direct_only: "1")

      assert filter_set1.eql?(filter_set2)
    end

    test "returns false when given nil" do
      filter_set = SponsorsExploreFilterSet.new
      refute filter_set.eql?(nil)
    end

    test "returns false when given something other than a filter set" do
      filter_set = SponsorsExploreFilterSet.new
      refute filter_set.eql?("foo")
    end

    test "returns true for two default filter sets" do
      filter_set1 = SponsorsExploreFilterSet.new
      filter_set2 = SponsorsExploreFilterSet.new

      assert filter_set1.eql?(filter_set2)
    end
  end

  context "#with" do
    test "returns a new filter set with the same setup as before but with the specified fields overridden" do
      original_filter_set = SponsorsExploreFilterSet.new(
        direct_only: true,
        ecosystems: %w[NPM RUBYGEMS],
        account_login: "foo",
        page: 2,
        sort_by: SponsorsExploreLoader::LEAST_USED_SORT,
      )

      new_filter_set = original_filter_set.with(account_login: "bar", ecosystems: %w[MAVEN PIP RUBYGEMS])

      assert_instance_of SponsorsExploreFilterSet, new_filter_set
      assert_predicate new_filter_set, :direct_dependencies_only?
      assert_equal "bar", new_filter_set.account_login
      assert_equal %w[MAVEN PIP RUBYGEMS], new_filter_set.ecosystems
      assert_equal 1, new_filter_set.page, "should have returned to first page when changing filters"
      assert_equal SponsorsExploreLoader::LEAST_USED_SORT, new_filter_set.sort_by
    end

    test "respects given page override" do
      original_filter_set = SponsorsExploreFilterSet.new(page: 2, sort_by: SponsorsExploreLoader::LEAST_USED_SORT)

      new_filter_set = original_filter_set.with(page: 3)

      assert_instance_of SponsorsExploreFilterSet, new_filter_set
      assert_equal 3, new_filter_set.page
      assert_equal SponsorsExploreLoader::LEAST_USED_SORT, new_filter_set.sort_by
    end
  end

  context "#to_s" do
    test "represents the active filters in the filter set" do
      filter_set = SponsorsExploreFilterSet.new(
        direct_only: false,
        ecosystems: %w[NPM RUBYGEMS],
        account_login: "foo",
        page: 2,
        sort_by: SponsorsExploreLoader::LEAST_USED_SORT,
      )
      assert_equal "account=foo&direct=0&ecosystems=NPM%2CRUBYGEMS&page=2&sort_by=LEAST_USED", filter_set.to_s
    end
  end
end
