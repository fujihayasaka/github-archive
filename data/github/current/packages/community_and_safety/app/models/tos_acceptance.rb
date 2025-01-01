# typed: true
# frozen_string_literal: true

class TosAcceptance < ApplicationRecord::Domain::Users

  HELP_DOCS_REPO_ID = 8189240 # github/help-docs

  before_create :set_sha

  validates_presence_of :user_id
  validates_length_of :sha, is: 40, allow_nil: true

  # Get a 40 character string representing the current blob OID the Help docs
  # This will help us track if the Privacy statement changes or if the repo
  # gets rearranged
  def self.current_sha
    begin
      GitHub.cache.fetch "tos-acceptance-sha", ttl: 10.minutes do
        get_tos_sha
      end
    rescue ActiveRecord::RecordNotFound => boom
      # rubocop:disable Style/HashSyntax
      GitHub.logger.error(boom)
      Failbot.report(ActiveRecord::RecordNotFound.new)
      GitHub::NULL_OID
    end
  end

  def self.get_tos_sha
    # Only check for a ToS SHA when github/help-docs is available.
    if GitHub.enterprise? || !Rails.env.production?
      return GitHub::NULL_OID
    end

    repo = Repositories::Public.find_active!(HELP_DOCS_REPO_ID)
    repo.default_oid
  end

  protected

  def set_sha
    self.sha = TosAcceptance.current_sha
  end
end
