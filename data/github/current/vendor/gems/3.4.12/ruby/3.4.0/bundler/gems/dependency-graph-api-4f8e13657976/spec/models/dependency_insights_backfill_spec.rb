require "rails_helper"

describe DependencyInsightsBackfill do
  before do
    factory do
      org_repo = Repository.create!({
        github_repository_id: 100,
        github_owner_id: 20,
        nwo: "github/monalisa"
      })

      PackageFactory.new("lodash", "1.0.0", :npm)
        .create!(published_at: "2018-10-10 20:33:33")

      PackageFactory.new("mocha", "4.0.0", :npm)
        .create!(published_at: "2018-09-05 20:33:33")

      PackageFactory.new("multi_xml", "0.5.2", :npm)
        .create!(published_at: "2018-10-09 20:33:33")

      given_manifest(
        github_repo_id: 100,
        manifest_type:  :package_lock_json,
        package_manager: :npm,
        filename:       "package-lock.json",
        path:           "/",
        revision:       1,
        dependencies:   [
          {
            package_name: "lodash",
            requirements: "= 1.0.0",
          },
          {
            package_name: "mocha",
            requirements: "= 4.0.0",
          },
          {
            package_name: "multi_xml",
            requirements: "= 0.5.2",
          },
        ]
      )

      DependencyInsightsBackfill.org_to_backfill(github_owner_id: org_repo.github_owner_id, source: nil)
    end
  end

  it "adds an org to backfill and updates materialized view with org package releases" do
    expected_backfill = DependencyInsightsBackfill.find_by(github_owner_id: 20)
    expect(expected_backfill.github_owner_id).to eq 20
    expect(expected_backfill.source).to eq nil
    expect(expected_backfill.last_backfilled_at).to eq nil

    # Backfills org it and updates materialized view
    DependencyInsightsBackfill.backfill_outstanding

    # Checks if entry in DependencyInsightsBackfill has been backfilled
    expected_backfill = DependencyInsightsBackfill.find_by(github_owner_id: 20)
    expect(expected_backfill.github_owner_id).to eq 20
    expect(expected_backfill.last_backfilled_at).to_not eq nil
    expect(expected_backfill.last_backfilled_at).to be_a_kind_of (Time)

    # Ensures materialized view has been updated with org package releases
    expect(Views::PackageReleaseDependentCount.where(github_owner_id: 20).count).to eq 3
  end

  it "removes an org from backfill table and removes all its associated rows from materialized views" do
    expected_backfill = DependencyInsightsBackfill.find_by(github_owner_id: 20)
    expect(expected_backfill.github_owner_id).to eq 20
    expect(expected_backfill.source).to eq nil
    expect(expected_backfill.last_backfilled_at).to eq nil

    # Backfills org it and updates materialized view
    DependencyInsightsBackfill.backfill_outstanding

    # Remove all data associated with given github owner id
    DependencyInsightsBackfill.remove_org(20)

    expected_backfill = DependencyInsightsBackfill.find_by(github_owner_id: 20)
    expect(expected_backfill).to be nil
  end
end
