# A cobbled together script for seeding a repository with a lot of Gemfiles. For use as
# inspiration only; unmaintained.
# I used this as part of SBOM generation profiling. The data seeded is not statistically
# representative of large repositories. I won't be maintaing this script, my intention is to
# replace it with a more well thought out, more statistically representative seeding script.


require "set"

require_relative "./../../config/environment"
require Rails.root.join("spec/support/manifest_factory")

def given_manifest(**args)
  ManifestFactory.new(**args).tap(&:create)
end

N_MANIFESTS = 10
N_DEPS_PER_MANIFEST = 3000

github_repository_id = 1

repository = Repository.where(github_repository_id: github_repository_id).first_or_create!

Manifest.connection.truncate(Manifest.table_name)
ManifestDependency.connection.truncate(ManifestDependency.table_name)
Package.connection.truncate(Package.table_name)
PackageRelease.connection.truncate(PackageRelease.table_name)


releases = Set.new

N_MANIFESTS.times do |proj_index|
  puts "Creating project-#{proj_index}..."
  manifest = Manifest.create!(
    repository_id: repository.id,
    manifest_type: Types::Manifest[:gemfile],
    package_manager: Types::PackageManager[:rubygems],
    filename:       "Gemfile",
    path:           "/project-#{proj_index}",
    revision:       1,
    latest_git_ref: "0bf1afea3fabb373484262713977f4ac7883a68a",
    last_pushed_at: Time.now
  )
  dependencies = N_DEPS_PER_MANIFEST.times
    .map do |dep_index|
      major, minor, patch = 3.times.map { rand(1..9) }
      releases.add(["package-#{dep_index}", "#{major}.#{minor}.#{patch}"])
      { package_name: "package-#{dep_index}", requirements: "= #{major}.#{minor}.#{patch}", last_seen_at_revision: 1, package_manager: Types::PackageManager[:rubygems] }
    end
    .each_slice(500) do |slice|
      manifest.dependencies.insert_all(slice)
    end
end

puts "Seeding package releases..."

releases
  .map do |r|
    { package_id: 1, package_name: r[0], name: r[1], license: "MIT" }
  end
  .each_slice(500) do |slice|
    PackageRelease.insert_all(slice)
  end
