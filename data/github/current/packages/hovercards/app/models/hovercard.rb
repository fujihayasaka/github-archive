# typed: true
# frozen_string_literal: true

class Hovercard
  # Valid contexts that can be looked up as a primary context, and their
  # corresponding key
  #
  # Update the github.v1.entities.HovercardContext hydro schema if these values change.
  SUBJECT_PREFIX_MAP = {
    advisory: Vulnerability,
    issue: Issue,
    sponsors_listing: SponsorsListing,
    organization: Organization,
    pull_request: PullRequest,
    repository: Repository,
    discussion: Discussion,
  }.stringify_keys.freeze

  # When showing lists of values, the number of entries to show before linking
  # for more
  LIST_LENGTH = 2

  def self.prefix_for(model)
    SUBJECT_PREFIX_MAP.key(model.class)
  end
end
