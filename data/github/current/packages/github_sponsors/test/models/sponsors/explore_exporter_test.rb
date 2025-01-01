# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::ExploreExporterTest < GitHub::TestCase
  fixtures do
    @viewer = create(:user, time_zone_name: nil)
    @sponsorable1 = create(:user, :sponsorable, login: "sponsorableTheFirst")
    @sponsorable2 = create(:organization, :sponsorable, login: "SecondSponsorable")

    @repo_sponsorable1 = create(:repository_sponsorable, :owner, sponsorable: @sponsorable1)
    @repo_sponsorable2 = create(:repository_sponsorable, :owner, sponsorable: @sponsorable2)
    @repo_sponsorable3 = create(:repository_sponsorable, :owner, sponsorable: @sponsorable2)

    tier_for_sponsorable1 = create(:sponsors_tier, :published,
      sponsors_listing: @sponsorable1.sponsors_listing, monthly_price_in_cents: 10_00)

    @sponsorable1_profile = create(:profile, user: @sponsorable1, name: "Some Nice Maintainer")
    @sponsorable1_user_sponsor = create(:sponsorship, :public, sponsorable: @sponsorable1,
      is_sponsor_opted_in_to_email: true, tier: tier_for_sponsorable1).sponsor
    @sponsorable1_org_sponsor = create(:sponsorship, :from_org, sponsorable: @sponsorable1).sponsor
    @sponsorable1.reload_user_metadata.update!(sponsors_public_and_private_count: 2, sponsors_count: 2)

    create(:user_metadata, user: @sponsorable2)
    @sponsorable2_goal = create(:sponsors_goal, :monthly_sponsorship_amount, listing: @sponsorable2.sponsors_listing,
      target_value: 5)
  end

  setup do
    repos = [@repo_sponsorable1, @repo_sponsorable2, @repo_sponsorable3].map(&:repository)
    stub_sponsorable_dependencies(repos)
  end

  context "#to_csv" do
    test "returns a string of CSV containing the sponsorable maintainers" do
      filter_set = SponsorsExploreFilterSet.new(sort_by: SponsorsExploreLoader::MOST_SPONSORS_SORT)
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )
      expected_header_row = "#{Sponsors::BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD}," \
        "#{Sponsors::ExploreExporter::SPONSORABLE_NAME_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_DEPENDENCIES_MAINTAINED_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_PROGRESS_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_DESCRIPTION_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_SPONSORS_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_ORG_SPONSORS_FIELD}," \
        "#{Sponsors::BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD}"
      expected_sponsorable1_row = "#{@sponsorable1},#{@sponsorable1_profile.name},1,,,2,1,"
      expected_sponsorable2_row = "#{@sponsorable2},,2,0,$5 per month,0,0,"

      result = exporter.to_csv

      assert_instance_of String, result
      lines = result.split("\n")
      assert_equal 3, lines.size, "should have a header row and two data rows, one for each maintainer"
      assert_equal expected_header_row, lines[0], "first line should have the headers"
      assert_equal expected_sponsorable1_row, lines[1],
        "second line should have sponsorable1's data because they have the most sponsors"
      assert_equal expected_sponsorable2_row, lines[2], "third line should have sponsorable2's data"
    end

    test "does not contain previous sponsorship information" do
      filter_set = SponsorsExploreFilterSet.new(sort_by: SponsorsExploreLoader::MOST_SPONSORS_SORT)
      explore_loader = SponsorsExploreLoader.new(viewer: @sponsorable1_user_sponsor, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @sponsorable1_user_sponsor,
        filter_set: filter_set,
      )
      expected_header_row = "#{Sponsors::BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD}," \
        "#{Sponsors::ExploreExporter::SPONSORABLE_NAME_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_DEPENDENCIES_MAINTAINED_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_PROGRESS_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_DESCRIPTION_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_SPONSORS_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_ORG_SPONSORS_FIELD}," \
        "#{Sponsors::BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD}"
      expected_sponsorable1_row = "#{@sponsorable1},#{@sponsorable1_profile.name},1,,,2,1,"
      expected_sponsorable2_row = "#{@sponsorable2},,2,0,$5 per month,0,0,"

      result = exporter.to_csv

      assert_instance_of String, result
      lines = result.split("\n")
      assert_equal 3, lines.size, "should have a header row and two data rows, one for each maintainer"
      assert_equal expected_header_row, lines[0], "first line should have the headers"
      assert_equal expected_sponsorable1_row, lines[1],
        "second line should have sponsorable1's data because they have the most sponsors"
      assert_equal expected_sponsorable2_row, lines[2], "third line should have sponsorable2's data"
    end

    test "includes all pages of results, ignoring pagination parameters in given filter set" do
      filter_set = SponsorsExploreFilterSet.new(page: 1, per_page: 1)
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )

      result = exporter.to_csv

      assert_instance_of String, result
      lines = result.split("\n")
      assert_equal 3, lines.size, "should have a header row and two data rows, one for each maintainer from all pages"
      assert_includes result, @sponsorable1.login
      assert_includes result, @sponsorable2.login
    end

    test "limits how many database queries are made per table" do
      filter_set = SponsorsExploreFilterSet.new
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )

      assert_query_count_per_table({
        sponsors_listings: 2, # 1 for the maintainers, 1 for featured listings
        sponsors_goals: 1,
        profiles: 1,
        repositories: 2, # 1 for the repos we should check for deps, 1 for verifying Dependency Graph API results
      }) do
        exporter.to_csv
      end
    end
  end

  context "#filename" do
    test "returns a name for the CSV file with relevant details" do
      filter_set = SponsorsExploreFilterSet.new(per_page: 1, page: 2)
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      time = Time.parse("2022-01-01 09:00:00 UTC")

      travel_to(time) do
        exporter = Sponsors::ExploreExporter.new(
          explore_loader: explore_loader,
          viewer: @viewer,
          filter_set: filter_set,
        )

        assert_equal "github-explore-sponsors-for-#{@viewer}-2022-01-01.csv", exporter.filename
      end
    end

    test "mentions when indirect dependencies are included" do
      filter_set = SponsorsExploreFilterSet.new(direct_only: false)
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )
      assert_includes exporter.filename, "-w-indirect-deps-"
    end

    test "includes single ecosystem filter" do
      filter_set = SponsorsExploreFilterSet.new(ecosystems: ["RUST"])
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )
      assert_includes exporter.filename, "-in-rust-"
    end

    test "includes multiple ecosystems filter" do
      filter_set = SponsorsExploreFilterSet.new(ecosystems: %w[RUST NPM])
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )
      assert_includes exporter.filename, "-in-npm-rust-"
    end

    test "considers the viewer's time zone" do
      filter_set = SponsorsExploreFilterSet.new
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)

      travel_to(Time.new(2014, 12, 31, 6, 0, 0, "-07:00")) do
        exporter = Sponsors::ExploreExporter.new(
          explore_loader: explore_loader,
          viewer: @viewer,
          filter_set: filter_set,
        )
        assert_match /2014-12-31/, exporter.filename

        @viewer.update!(time_zone_name: "Pacific/Kiritimati")
        assert_match /2015-01-01/, exporter.filename
      end
    end
  end

  context "#sanitize_login_or_name" do
    test "removes equals signs name" do
      # Login validation does not allow for '='
      sponsorable = create(:user, :sponsorable, login: "sponsorable")
      sponsorable_profile = create(:profile, user: sponsorable, name: "=spon=sorable=")
      repo_sponsorable = create(:repository_sponsorable, :owner, sponsorable: sponsorable)
      repos = [repo_sponsorable].map(&:repository)
      stub_sponsorable_dependencies(repos)

      assert sponsorable_profile.name.start_with?("=")
      assert sponsorable_profile.name.end_with?("=")
      assert_operator sponsorable_profile.name.count("="), :>, 2, "should have at least one '=' in the middle"

      filter_set = SponsorsExploreFilterSet.new(sort_by: SponsorsExploreLoader::MOST_SPONSORS_SORT)
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )
      expected_header_row = "#{Sponsors::BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD}," \
        "#{Sponsors::ExploreExporter::SPONSORABLE_NAME_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_DEPENDENCIES_MAINTAINED_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_PROGRESS_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_DESCRIPTION_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_SPONSORS_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_ORG_SPONSORS_FIELD}," \
        "#{Sponsors::BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD}"
      expected_sponsorable_row = "sponsorable,sponsorable,1,,,0,0,"

      result = exporter.to_csv

      assert_instance_of String, result
      lines = result.split("\n")
      assert_equal expected_header_row, lines[0], "first line should have the headers"
      assert_equal expected_sponsorable_row, lines[1]
    end

    test "removes plus signs from login and name" do
      # Login validation does not allow for '+'
      sponsorable = create(:user, :sponsorable, login: "sponsorable")
      sponsorable_profile = create(:profile, user: sponsorable, name: "+spon+sorable+")
      repo_sponsorable = create(:repository_sponsorable, :owner, sponsorable: sponsorable)
      repos = [repo_sponsorable].map(&:repository)
      stub_sponsorable_dependencies(repos)

      assert sponsorable_profile.name.start_with?("+")
      assert sponsorable_profile.name.end_with?("+")
      assert_operator sponsorable_profile.name.count("+"), :>, 2, "should have at least one '+' in the middle"

      filter_set = SponsorsExploreFilterSet.new(sort_by: SponsorsExploreLoader::MOST_SPONSORS_SORT)
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )
      expected_header_row = "#{Sponsors::BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD}," \
        "#{Sponsors::ExploreExporter::SPONSORABLE_NAME_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_DEPENDENCIES_MAINTAINED_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_PROGRESS_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_DESCRIPTION_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_SPONSORS_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_ORG_SPONSORS_FIELD}," \
        "#{Sponsors::BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD}"
      expected_sponsorable_row = "sponsorable,sponsorable,1,,,0,0,"

      result = exporter.to_csv

      assert_instance_of String, result
      lines = result.split("\n")
      assert_equal expected_header_row, lines[0], "first line should have the headers"
      assert_equal expected_sponsorable_row, lines[1]
    end

    test "removes minus signs from name but not from login" do
      # Login validation does not allow for '-' at the beginning or end
      sponsorable = create(:user, :sponsorable, login: "spon-sorable")
      sponsorable_profile = create(:profile, user: sponsorable, name: "-spon-sorable-")
      repo_sponsorable = create(:repository_sponsorable, :owner, sponsorable: sponsorable)
      repos = [repo_sponsorable].map(&:repository)
      stub_sponsorable_dependencies(repos)

      assert sponsorable_profile.name.start_with?("-")
      assert sponsorable_profile.name.end_with?("-")
      assert_operator sponsorable_profile.name.count("-"), :>, 2, "should have at least one '-' in the middle"

      filter_set = SponsorsExploreFilterSet.new(sort_by: SponsorsExploreLoader::MOST_SPONSORS_SORT)
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )
      expected_header_row = "#{Sponsors::BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD}," \
        "#{Sponsors::ExploreExporter::SPONSORABLE_NAME_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_DEPENDENCIES_MAINTAINED_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_PROGRESS_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_DESCRIPTION_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_SPONSORS_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_ORG_SPONSORS_FIELD}," \
        "#{Sponsors::BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD}"
      expected_sponsorable_row = "spon-sorable,sponsorable,1,,,0,0,"

      result = exporter.to_csv

      assert_instance_of String, result
      lines = result.split("\n")
      assert_equal expected_header_row, lines[0], "first line should have the headers"
      assert_equal expected_sponsorable_row, lines[1]
    end

    test "removes at signs from login and name" do
      # Login validation does not allow for '@'
      sponsorable = create(:user, :sponsorable, login: "sponsorable")
      sponsorable_profile = create(:profile, user: sponsorable, name: "@spon@sorable@")
      repo_sponsorable = create(:repository_sponsorable, :owner, sponsorable: sponsorable)
      repos = [repo_sponsorable].map(&:repository)
      stub_sponsorable_dependencies(repos)

      assert sponsorable_profile.name.start_with?("@")
      assert sponsorable_profile.name.end_with?("@")
      assert_operator sponsorable_profile.name.count("@"), :>, 2, "should have at least one '@' in the middle"

      filter_set = SponsorsExploreFilterSet.new(sort_by: SponsorsExploreLoader::MOST_SPONSORS_SORT)
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )
      expected_header_row = "#{Sponsors::BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD}," \
        "#{Sponsors::ExploreExporter::SPONSORABLE_NAME_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_DEPENDENCIES_MAINTAINED_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_PROGRESS_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_DESCRIPTION_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_SPONSORS_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_ORG_SPONSORS_FIELD}," \
        "#{Sponsors::BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD}"
      expected_sponsorable_row = "sponsorable,sponsorable,1,,,0,0,"

      result = exporter.to_csv

      assert_instance_of String, result
      lines = result.split("\n")
      assert_equal expected_header_row, lines[0], "first line should have the headers"
      assert_equal expected_sponsorable_row, lines[1]
    end

    test "removes semicolons from login and name" do
      # Login validation does not allow for ';'
      sponsorable = create(:user, :sponsorable, login: "sponsorable")
      sponsorable_profile = create(:profile, user: sponsorable, name: ";spon;sorable;")
      repo_sponsorable = create(:repository_sponsorable, :owner, sponsorable: sponsorable)
      repos = [repo_sponsorable].map(&:repository)
      stub_sponsorable_dependencies(repos)

      assert sponsorable_profile.name.start_with?(";")
      assert sponsorable_profile.name.end_with?(";")
      assert_operator sponsorable_profile.name.count(";"), :>, 2, "should have at least one ';' in the middle"

      filter_set = SponsorsExploreFilterSet.new(sort_by: SponsorsExploreLoader::MOST_SPONSORS_SORT)
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )
      expected_header_row = "#{Sponsors::BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD}," \
        "#{Sponsors::ExploreExporter::SPONSORABLE_NAME_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_DEPENDENCIES_MAINTAINED_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_PROGRESS_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_DESCRIPTION_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_SPONSORS_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_ORG_SPONSORS_FIELD}," \
        "#{Sponsors::BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD}"
      expected_sponsorable_row = "sponsorable,sponsorable,1,,,0,0,"

      result = exporter.to_csv

      assert_instance_of String, result
      lines = result.split("\n")
      assert_equal expected_header_row, lines[0], "first line should have the headers"
      assert_equal expected_sponsorable_row, lines[1]
    end

    test "removes null byte from login and name" do
      # Login validation does not allow for '%=00'
      sponsorable = create(:user, :sponsorable, login: "sponsorable")
      sponsorable_profile = create(:profile, user: sponsorable, name: "%=00spon%=00sorable%=00")
      repo_sponsorable = create(:repository_sponsorable, :owner, sponsorable: sponsorable)
      repos = [repo_sponsorable].map(&:repository)
      stub_sponsorable_dependencies(repos)

      assert sponsorable_profile.name.start_with?("%=00")
      assert sponsorable_profile.name.end_with?("%=00")
      assert_operator sponsorable_profile.name.count("%=00"), :>, 2, "should have at least one '%=00' in the middle"

      filter_set = SponsorsExploreFilterSet.new(sort_by: SponsorsExploreLoader::MOST_SPONSORS_SORT)
      explore_loader = SponsorsExploreLoader.new(viewer: @viewer, filter_set: filter_set)
      exporter = Sponsors::ExploreExporter.new(
        explore_loader: explore_loader,
        viewer: @viewer,
        filter_set: filter_set,
      )
      expected_header_row = "#{Sponsors::BulkSponsorshipImportProcessor::SPONSORABLE_LOGIN_FIELD}," \
        "#{Sponsors::ExploreExporter::SPONSORABLE_NAME_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_DEPENDENCIES_MAINTAINED_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_PROGRESS_FIELD}," \
        "#{Sponsors::ExploreExporter::GOAL_DESCRIPTION_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_SPONSORS_FIELD}," \
        "#{Sponsors::ExploreExporter::TOTAL_ORG_SPONSORS_FIELD}," \
        "#{Sponsors::BulkSponsorshipImportProcessor::DOLLAR_AMOUNT_FIELD}"
      expected_sponsorable_row = "sponsorable,sponsorable,1,,,0,0,"

      result = exporter.to_csv

      assert_instance_of String, result
      lines = result.split("\n")
      assert_equal expected_header_row, lines[0], "first line should have the headers"
      assert_equal expected_sponsorable_row, lines[1]
    end
  end

  def stub_sponsorable_dependencies(repos)
    fake_client = FakeDependencyGraphClient.new(expected_calls: nil, response: {
      data: { repositoryOwnerDependencies: { dependencies: repos.map(&:id) } },
    })
    DependencyGraph::Query.stubs(:default_backend).returns(fake_client)
  end
end
