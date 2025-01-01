require "rails_helper"

RSpec.describe LoadPackageMetadataJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:release_attr) do
    {
      package_manager: :rubygems,
      package_name: "rails",
      version: "7.0.0",
      license: "MIT",
      published_at: Date.iso8601("2022-01-31"),
      unpublished_at: nil, # OSPO events do not capture this
      source_url: "https://github.com/some/public-repo"
    }
  end

  let(:private_repo_release_attr) do
    {
      package_manager: :rubygems,
      package_name: "rails",
      version: "7.0.0",
      license: "MIT",
      published_at: Date.iso8601("2022-01-31"),
      unpublished_at: nil, # OSPO events do not capture this
      source_url: "https://github.com/some/private-repo"
    }
  end

  let(:authoritative_attr) do
    {
      package_manager: :rust,
      package_name: "foobar",
      version: "1.2.3",
      license: "Apache-2.0 OR MIT",
      published_at: Date.iso8601("2022-01-31"),
      unpublished_at: nil, # OSPO events do not capture this
      source_url: "https://github.com/some/public-repo"
    }
  end


  let(:npm_package_attributions) do
    {
      package_manager: :npm,
      package_name: "jest-runner-eslint",
      version: "0.7.6",
      source_url: "https://github.com/jest-community/jest-runner-eslint/tree/d09d7885ef1cf958016aa75d1545fe7ed4444dc0",
      home_url: "https://github.com/jest-community/jest-runner-eslint",
      license: "MIT",
      clearly_defined_score: 77,
      attributions: ["copyright anna john doe", "Copyright Anna John Doe", "Cöpyright Ånnä Jöhn Döё"]
    }
  end

  before do
    factory.given_repository nwo: "some/public-repo", github_repository_id: 123
    factory.given_repository nwo: "crabby/project", github_repository_id: 789
    factory.given_repository nwo: "jest-community/jest-runner-eslint", github_repository_id: 456
  end

  it "creates Package and PackageRelease records if none exist " do
    expect {
      LoadPackageMetadataJob.perform_now Packages::PackageRelease.new(**release_attr)
    }.to change { Package.count }.by(1)
     .and change { PackageRelease.count }.by(1)

    package = Package.find_by(name: release_attr[:package_name], package_manager: Types::PackageManager[:rubygems])
    expect(package).to be_present
    expect(package.repository_id_certainty).to eq PackageToRepoMapping::Certainty::CLEARLY_DEFINED_MATCH
    expect(package.repository_id).to eq 123
    expect(package.updated_at).to eq package.created_at

    package_release = package.releases.find_by(name: release_attr[:version])
    expect(package_release).to be_present
    expect(package_release.encoded).to be_present
    expect(package_release.license).to eq release_attr[:license]
    expect(package_release.source_url).to eq release_attr[:source_url]
    expect(package_release.repository_id_certainty).to eq PackageToRepoMapping::Certainty::CLEARLY_DEFINED_MATCH
    expect(package_release.repository_id).to eq 123
    expect(package_release.updated_at).to eq package_release.created_at
  end

  it "does not map private repos" do
    factory.given_repository nwo: "some/private-repo", public: false
    expect {
      LoadPackageMetadataJob.perform_now(
        Packages::PackageRelease.new(**private_repo_release_attr)
      )
    }.to change { Package.count }.by(1)
    .and change { PackageRelease.count }.by(1)

    package = Package.find_by(name: private_repo_release_attr[:package_name], package_manager: Types::PackageManager[:rubygems])
    expect(package).to be_present
    expect(package.repository_id).to be_nil
    expect(package.repository_id_certainty).to eq PackageToRepoMapping::Certainty::NULL

    package_release = package.releases.find_by(name: private_repo_release_attr[:version])
    expect(package_release).to be_present
    expect(package_release.source_url).to be_nil
    expect(package_release.repository_id).to be_nil
    expect(package_release.repository_id_certainty).to eq PackageToRepoMapping::Certainty::NULL
  end

  context "existing records " do
    it "updates the relevant fields" do
      create_ts = Time.now.round.utc
      travel_to(create_ts) do
        factory do
          given_package("rails", "7.0.0", :rubygems)
          .update_package_release({ license: "Apache-2.0" })
          .update_repository_mapping(github_repository_id: 456)
        end
      end

      travel_to(create_ts + 1.hour) do
        expect {
          LoadPackageMetadataJob.perform_now Packages::PackageRelease.new(**release_attr)
        }.to change { Package.count }.by(0)
        .and change { PackageRelease.count }.by(0)
      end

      package = Package.find_by(name: release_attr[:package_name], package_manager: Types::PackageManager[:rubygems])
      expect(package.last_published_at).to eq Date.iso8601("2022-01-31")
      expect(package.repository_id).to eq 123

      package_release = package.releases.find_by(name: release_attr[:version])
      expect(package_release.published_at).to eq Date.iso8601("2022-01-31")
      expect(package_release.unpublished_at).to be_nil
      expect(package_release.license).to eq release_attr[:license]
      expect(package_release.source_url).to eq release_attr[:source_url]
      expect(package_release.repository_id_certainty).to eq PackageToRepoMapping::Certainty::CLEARLY_DEFINED_MATCH
      expect(package_release.repository_id).to eq 123

      expect(package_release.updated_at - package_release.created_at).to eq 1.hour.to_i
    end

    it "updates the relevant fields only for authoritative, existing record" do
      orig_package_ts = Time.now.round.utc
      travel_to(orig_package_ts) do
        factory do
          # simulate the fact that Rust pkg-repo mappings are considered "authoritative"
          given_package("foobar", "1.2.3", :rust)
            .update_package({
              last_published_at: orig_package_ts,
              repository_id: 789,
              repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH,
            })
            .update_package_release({
              license: "Apache-2.0",
              published_at: orig_package_ts,
              repository_id: 789,
              source_url: "https://github.com/crabby/project",
              repository_id_certainty: PackageToRepoMapping::Certainty::POSITIVE_MATCH,
            })
        end
      end

      travel_to(orig_package_ts + 1.hour) do
        expect {
          LoadPackageMetadataJob.perform_now Packages::PackageRelease.new(**authoritative_attr)
        }.to change { Package.count }.by(0)
        .and change { PackageRelease.count }.by(0)
      end

      package = Package.find_by(name: authoritative_attr[:package_name], package_manager: Types::PackageManager[:rust])
      expect(package.last_published_at).to eq orig_package_ts
      expect(package.repository_id).to eq 789
      expect(package.updated_at - package.created_at).to eq 1.hour.to_i

      package_release = package.releases.find_by(name: authoritative_attr[:version])
      expect(package_release.published_at).to eq orig_package_ts
      expect(package_release.unpublished_at).to be_nil
      expect(package_release.license).to eq authoritative_attr[:license]
      expect(package_release.source_url).to eq "https://github.com/crabby/project"
      expect(package_release.repository_id_certainty).to eq PackageToRepoMapping::Certainty::POSITIVE_MATCH
      expect(package_release.repository_id).to eq 789
    end

    it "doesnt update fields for which OSPO data has lower presedence" do
      factory do
        given_package("rails", "7.0.0", :rubygems, last_published_at: Time.iso8601("2022-04-26T15:06:14Z"))
        .update_package_release({ license: "Apache-2.0", published_at: Time.iso8601("2022-04-26T15:06:14Z"), unpublished_at: Time.iso8601("2023-01-26T15:06:14Z") })
        .update_repository_mapping(github_repository_id: 456, repository_id_certainty: PackageToRepoMapping::Certainty::OVERRIDE)
      end

      expect {
        LoadPackageMetadataJob.perform_now Packages::PackageRelease.new(**release_attr)
      }.to change { Package.count }.by(0)
     .and change { PackageRelease.count }.by(0)

      package = Package.find_by(name: release_attr[:package_name], package_manager: Types::PackageManager[:rubygems])
      expect(package.last_published_at).to eq Time.iso8601("2022-04-26T15:06:14Z")
      expect(package.repository_id).to eq 456

      package_release = package.releases.find_by(name: release_attr[:version])
      expect(package_release.published_at).to eq Time.iso8601("2022-04-26T15:06:14Z")
      expect(package_release.unpublished_at).to eq Time.iso8601("2023-01-26T15:06:14Z")
      expect(package_release.source_url).not_to eq release_attr[:source_url]
      expect(package_release.repository_id_certainty).to eq PackageToRepoMapping::Certainty::OVERRIDE
      expect(package_release.repository_id).to eq 456
    end
  end

  context "dry run" do
    before { allow(DependencyGraph.logger).to receive(:info) }

    it "logs create text for new record" do
      expect {
        LoadPackageMetadataJob.perform_now Packages::PackageRelease.new(**release_attr), persist_data: false
      }.to change { Package.count }.by(0)
       .and change { PackageRelease.count }.by(0)

      expect(DependencyGraph.logger).to have_received(:info).with("Creating package", hash_including({
        "gh.dependency_graph.package_manager" => release_attr[:package_manager],
        "gh.dependency_graph.package.name" => release_attr[:package_name],
      })).once
      expect(DependencyGraph.logger).to have_received(:info).with("Creating package release", hash_including({
        "gh.dependency_graph.package_manager" => release_attr[:package_manager],
        "gh.dependency_graph.package.name" => release_attr[:package_name],
      })).once
    end

    it "logs update text for duplicate record" do
      factory.given_package("rails", "7.0.0", :rubygems)

      expect {
        LoadPackageMetadataJob.perform_now Packages::PackageRelease.new(**release_attr), persist_data: false
      }.to change { Package.count }.by(0)
       .and change { PackageRelease.count }.by(0)

      expect(DependencyGraph.logger).to have_received(:info).with("Updating package", hash_including({
        "gh.dependency_graph.package_manager" => release_attr[:package_manager],
        "gh.dependency_graph.package.name" => release_attr[:package_name],
      })).once
      expect(DependencyGraph.logger).to have_received(:info).with("Updating package release", hash_including({
        "gh.dependency_graph.package_manager" => release_attr[:package_manager],
        "gh.dependency_graph.package.name" => release_attr[:package_name],
        "gh.dependency_graph.package.version" => release_attr[:version],
      })).once
    end
  end

  context "attributions" do
    it "inserts attribution records according to accents and cases" do
      expect {
        LoadPackageMetadataJob.perform_now Packages::PackageRelease.new(**npm_package_attributions)
      }.to change { Attribution.count }.by(3)
    end

    it "doesn't insert duplicate attributions on repeated job run" do
      a = npm_package_attributions.merge(attributions: ["test"])
      expect {
        LoadPackageMetadataJob.perform_now Packages::PackageRelease.new(**a)
      }.to change { Attribution.count }.by(1)

      expect {
        LoadPackageMetadataJob.perform_now Packages::PackageRelease.new(**a)
      }.to change { Attribution.count }.by(0)
    end
  end
end
