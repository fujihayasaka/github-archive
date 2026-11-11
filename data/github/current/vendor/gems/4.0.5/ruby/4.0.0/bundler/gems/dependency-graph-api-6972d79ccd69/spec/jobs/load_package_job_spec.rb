require "rails_helper"

describe LoadPackageJob do
  describe "#perform" do
    it "loads the package" do
      package = Packages::PackageRelease.new(
        package_manager: Types::PackageManager[:npm],
        package_name: "express",
        version: "4.18.0"
      )

      loader = instance_double(Ingest::PackageLoader, load: nil)
      allow(Ingest::PackageLoader).to receive(:new).with(package).and_return(loader)

      expect(loader).to receive(:load)

      LoadPackageJob.new.perform(package)
    end
  end

  it "skips processing when the package has not changed" do
    package = Packages::PackageRelease.new(
      package_manager: Types::PackageManager[:npm],
      package_name: "express",
      version: "4.18.0"
    )
    package_to_skip = Packages::PackageRelease.new(
      package_manager: Types::PackageManager[:npm],
      package_name: "express",
      version: "4.18.0",
      description: "Changed description"
    )

    LoadPackageJob.new.perform(package)

    expect {
      LoadPackageJob.new.perform(package_to_skip)
    }.to have_instrumented_increment("etl.ingest.skip_job", {
      stage: "packages",
      package_manager: "npm"
    })
  end

  it "does not skip processing when the package source_url has changed" do
    new_repo = Repository.create(github_repository_id: 2448, nwo: "neworg/jquery")

    package = Packages::PackageRelease.new(
      package_manager: Types::PackageManager[:npm],
      package_name: "express",
      version: "4.18.0"
    )
    changed_source_url = Packages::PackageRelease.new(
      package_manager: Types::PackageManager[:npm],
      package_name: "express",
      version: "4.18.0",
      source_url: "https://github.com/neworg/jquery"
    )

    LoadPackageJob.new.perform(package)
    LoadPackageJob.new.perform(changed_source_url)

    expect(PackageRelease.find_by(package_name: "express", name: "4.18.0").repository_id).to eq new_repo.github_repository_id
  end
end
