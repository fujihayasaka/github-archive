# typed: true
# frozen_string_literal: true

# A small value class that provides an interface for our review code to update
# the Advisory
#
# This class will be deprecated as Advisory review moves to the standalone
# Advisory DB service
class RepositoryAdvisory::GitHubReview
  def self.for(repository_advisory)
    new(repository_advisory)
  end

  def self.for_ghsa_id(ghsa_id)
    new RepositoryAdvisory.find_by!(ghsa_id: ghsa_id)
  end

  def initialize(repository_advisory)
    @repository_advisory = repository_advisory
  end

  def set_published
    @repository_advisory.add_review_state_event("github_published")
  end

  def set_withdrawn
    @repository_advisory.add_review_state_event("github_withdrawn")
  end
end
