# typed: true
# frozen_string_literal: true

class TosAcceptance < ApplicationRecord::Domain::Users
  HELP_DOCS_REPO_ID = 8189240 # https://github.com/github/docs-internal

  before_create :set_sha

  validates_presence_of :user_id
  validates_length_of :sha, is: 40, allow_nil: true

  # Get a 40 character string representing the current blob OID the Help docs
  # This will help us track if the Privacy statement changes or if the repo
  # gets rearranged
  def self.current_sha
    begin
      GitHub.cache.fetch "tos-acceptance-sha", ttl: 10.minutes do
        tos_sha
      end
    rescue ActiveRecord::RecordNotFound => boom
      GitHub.logger.error(boom)
      Failbot.report(ActiveRecord::RecordNotFound.new)
      GitHub::NULL_OID
    end
  end

  def self.tos_sha
    return GitHub::NULL_OID unless read_sha_from_docs_repo?

    docs_repo.default_oid || GitHub::NULL_OID
  end

  def self.read_sha_from_docs_repo?
    # Only check for a ToS SHA when https://github.com/github/docs-internal exists.
    !GitHub.enterprise? && Rails.env.production?
  end

  def self.docs_repo
    Repositories::Public.find_active!(HELP_DOCS_REPO_ID)
  end

  protected

  def set_sha
    self.sha = TosAcceptance.current_sha
  end
end
