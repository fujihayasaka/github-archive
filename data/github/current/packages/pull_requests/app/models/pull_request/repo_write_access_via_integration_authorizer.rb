# typed: true
# frozen_string_literal: true

class PullRequest
  class RepoWriteAccessViaIntegrationAuthorizer
    attr_reader :repo, :actor

    def initialize(repo:, actor:)
      @repo = repo
      @actor = actor
    end

    # Public: Is the actor allowed to write to the repo?
    def allow?
      # If the actor is not authenticating via granular actor
      # we can rely on PullRequest model validations
      # to ensure that the user has write access to the repo
      return true unless actor&.using_auth_via_granular_actor?

      repo_contents_writable?
    end

    private

    def repo_contents_writable?
      grant = ProgrammaticActor::Grant.with(actor).with_target(repo.owner)
      grant && repo.resources.contents.writable_by?(grant)
    end
  end
end
