# typed: true
# frozen_string_literal: true

require_relative "../../../../releases/test/releases/releases_public_package_boundary_test"

module ReposPublicPackageBoundary
  extend self

  # Until we have meaningful public interfaces that do these sorts of things, for testing purposes let's define
  # some methods that will fairly exercise GitHub::SQLCheckers::DomainIsolation::*StatementChecker classes.

  # This method is good because it uses the public interface of the Releases package
  def good_find_repo_and_published_release_count_by_id(id)
    release_count = ::ReleasesPublicPackageBoundary.published_release_count_for_repository(id)
    repo = Repository.find(id)
    [repo, release_count]
  end

  # This method is bad because it uses the private interface of the Releases package
  def bad_find_repo_and_published_release_count_by_id(id)
    release_count = ::Release.published.where(repository_id: id).count
    repo = Repository.find(id)
    [repo, release_count]
  end

  extend GitHub::DomainIsolation::PackageBoundary
end
