
task sync_vulnerabilities: :environment do
  VulnerableVersionRange.sync
end

task rebuild_package_release_vulnerabilities_count: :environment do
  Views::PackageReleaseVulnerabilitiesCount.rebuild
end
