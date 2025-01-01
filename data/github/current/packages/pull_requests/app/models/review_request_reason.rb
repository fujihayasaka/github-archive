# typed: true
# frozen_string_literal: true

class ReviewRequestReason < ApplicationRecord::Domain::IssuesPullRequests

  CODEOWNERS = "codeowners"

  belongs_to :review_request

  validates :repository_id, presence: true, on: :create

  with_options if: :codeowners? do |codeowners|
    codeowners.validates :codeowners_tree_oid,  presence: true, format: /\A[a-f0-9]{40}\Z/
    codeowners.validates :codeowners_path,      presence: true
    codeowners.validates :codeowners_line,      presence: true, numericality: true
    codeowners.validates :codeowners_pattern,   presence: true
  end

  before_validation :set_repository_id

  # Public: The type of reason.
  #
  # Currently hardcoded to "codeowners" as that is the only reason we support
  # since manual requests do not have associated reasons.
  #
  # Returns a String.
  def reason_type
    CODEOWNERS
  end

  def codeowners?
    reason_type == CODEOWNERS
  end

  def async_base_repository
    async_review_request.then(&:async_pull_request).then(&:async_base_repository)
  end

  def async_codeowners_commit
    return Promise.resolve(nil) unless codeowners?
    return @async_codeowners_commit if defined?(@async_codeowners_commit)

    @async_codeowners_commit = async_base_repository.then do |repository|
      Platform::Loaders::GitObject.load(repository, codeowners_tree_oid, expected_type: :commit)
    end
  end

  def async_codeowners_file
    return Promise.resolve(nil) unless codeowners?
    return @async_codeowners_file if defined?(@async_codeowners_file)

    @async_codeowners_file = Promise.all([
      async_base_repository, async_codeowners_commit],
    ).then do |repository, commit|
      next unless commit
      revision = Platform::Models::CommitRevision.new(repository, commit)
      revision.async_load_file(path: codeowners_path)
    end
  end

  def async_codeowners_path_uri
    return Promise.resolve(nil) unless codeowners?

    async_codeowners_file.then do |committish_file|
      next unless committish_file

      committish_file.uri.dup.tap do |uri|
        uri.fragment = "L#{codeowners_line}"
      end
    end
  end

  private def set_repository_id
    self.repository_id = review_request&.repository_id
  end
end
