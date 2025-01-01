require_relative "../../app/models/versioning/encoded_version"

module OneOffImporters
  class Actions < Base
    # Runs the ActionsPackageJob, given an action repo and version

    # Request and parsing methods not needed since we're simply performing this job
    def request; end

    def parse; end

    def run
      return unless package_name && package_version

      ActionsPackageJob.perform_later([{ name: package_name, version: package_version }])

      1 # run is expected to return number of releases imported
    end
  end
end
