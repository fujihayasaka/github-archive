# typed: true
# frozen_string_literal: true

class RepositoryLicense < ApplicationRecord::Domain::Repositories

  belongs_to :repository

  validates_presence_of :repository_id
  validates_uniqueness_of :filepath, scope: :repository_id, allow_nil: true
  validates_presence_of :license_id
  validates_inclusion_of :license_id, in: License.valid_license_ids,
    message: "%{value} is not a valid license id."

  FILENAME_REGEXP = /\A(licen[sc]e|copying)(-)?(-\D+)?(\z|\..)/i

  class << self
    # Returns the string key of a detected license, otherwise "other" or "no-license"
    def detect_license(repo, ref = repo.default_oid)
      ref = repo.ref_to_sha(ref) unless ref == repo.default_oid
      repo.rpc.detect_license(ref)
    rescue GitRPC::BadRepositoryState
      "other" # license file is too small for git-based detection
    rescue GitRPC::InvalidRepository, GitRPC::ObjectMissing, GitRPC::Failure
      "no-license"
    end

    def detect_licenses(repo, ref = repo.default_oid)
      ref = repo.ref_to_sha(ref) unless ref == repo.default_oid
      license_file_information = repo.rpc.detect_licenses(ref)
      valid_license_files(license_file_information[:licenses])
    rescue GitRPC::InvalidRepository, GitRPC::ObjectMissing, GitRPC::Failure
      [] #on failure, use no licenses state
    end

    def set_licenses(repo)
      license_files = detect_licenses(repo)

      if license_files.empty?
        # if there aren't any valid licenses found, destroy any that may have existed previously.
        repo.repository_licenses.destroy_all unless repo.repository_licenses.empty?
      else
        transaction do
          repo.repository_licenses.destroy_all unless repo.repository_licenses.empty?
          license_files.each do |license_file|
            repo.repository_licenses.create!(license_id: License.find_by_key(license_file[:license_key], hidden: true).id, filepath: license_file[:filepath])
          end
        end
      end
    end

    # Detect a repository's license and write to the database
    # Returns the License object, or nil if no license or a private repo
    def set_license(repo, ref: repo.default_oid)
      key = RepositoryLicense.detect_license(repo, ref)
      filepath = RepositoryLicense.detect_licenses(repo, ref).first.try(:[], :filepath)
      # Temporary fix for inconsistency with GitRPC
      # See https://github.com/github/gitrpc/pull/353
      key = "other" if key == "unknown"

      license = License.find_by_key(key, hidden: true)
      # Value in the database is accurate or we don't want to persist the license on a non-default branch.
      return license if ref != repo.default_oid || license == repo.license

      GitHub.dogstats.increment "license.set", tags: [
        "license:#{license.nil? ? "no-license" : license.key}",
        "from_license:#{repo.license.nil? ? "no-license" : repo.license.key}",
      ]

      ActiveRecord::Base.connected_to(role: :writing) do
        if license.nil? || license.key == "no-license"
          repo.repository_license.destroy if repo.repository_license
          return nil
        elsif repo.repository_license
          repo.repository_license.update! license_id: license.id, filepath: filepath
        else
          RepositoryLicense.create! license_id: license.id, repository: repo, filepath: filepath
        end
      end
      license
    end

    def push_changed_license?(push)
      return false if push.branch_name != push.repository.default_branch
      return true  if push.initial_commit? # initial commit
      return false unless push.changed_files
      push.changed_files.any? do |file|
        (file.path.present? && Licensee::ProjectFiles::LicenseFile.name_score(file.path) > 0) ||
          (file.previous_path.present? && Licensee::ProjectFiles::LicenseFile.name_score(file.previous_path) > 0)
      end
    end

    private

    def valid_license_files(license_files)
      license_files
        .yield_self { |files| with_valid_license_keys(files) }
        .yield_self { |files| without_duplicate_filepaths(files) }
    end

    def with_valid_license_keys(licenses)
      licenses.select { |license| license[:license_key] != "no-license" }
    end

    def without_duplicate_filepaths(licenses)
      licenses.uniq { |license| license[:filepath].downcase }
    end
  end

  # Since License is not an ActiveRecord object, stub expected helper methods
  def license
    License.find_by_id(license_id)
  end

  def license=(license)
    self.license_id = license.id
  end
end
