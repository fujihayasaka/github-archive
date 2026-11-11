# typed: true
# frozen_string_literal: true

class ReviewRequestReason < ApplicationRecord::Domain::IssuesPullRequests

  belongs_to :review_request

  validates :repository_id, presence: true, on: :create
  validates :reason_type, presence: true, on: :create

  COPILOT_REASON_TYPES = %w[copilot_org_setting copilot_repo_setting copilot_user_setting].freeze

  enum :reason_type, {
    codeowners: "codeowners",
    # we previously logged a generic "copilot" reason type, so it's here for backward compatibility
    copilot: "copilot",
    # now we support specific copilot reason types
    copilot_org_setting: "copilot_org_setting",
    copilot_repo_setting: "copilot_repo_setting",
    copilot_user_setting: "copilot_user_setting",
  }

  with_options if: :codeowners? do |codeowners|
    codeowners.validates :codeowners_tree_oid,  presence: true, format: /\A[a-f0-9]{40}\Z/
    codeowners.validates :codeowners_path,      presence: true
    codeowners.validates :codeowners_line,      presence: true, numericality: true
    codeowners.validates :codeowners_pattern,   presence: true
  end

  before_validation :set_repository_id

  def codeowners?
    # reason_type was not persisted until the "copilot" type was added
    # therefore, consider a nil reason_type to count as "codeowners"
    reason_type.nil? || reason_type == "codeowners"
  end

  def copilot?
    # reason_type=copilot was initiatilly used, we later added more specific reasons
    COPILOT_REASON_TYPES.include?(reason_type) || reason_type == "copilot"
  end

  def async_base_repository
    async_review_request.then { |x| T.must(x).async_pull_request }.then(&:async_base_repository)
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
    self.repository_id = review_request&.repository_id || review_request&.pull_request&.repository_id
  end
end
