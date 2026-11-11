# typed: true
# frozen_string_literal: true

class PullRequest
  class ForkCollabAccessViaIntegrationAuthorizer

    attr_accessor :head_repository, :base_repository, :actor

    def initialize(head_repository:, base_repository:, actor:)
      @head_repository = head_repository
      @base_repository = base_repository
      @actor = actor
    end

    # Public: Is the actor allowed to grant fork collab access to the
    # pull's head ref?
    #
    # Returns a Boolean.
    def allow?
      # The fork collab setting only applies to cross repository pulls, so we can
      # just allow here and skip unnecessary work since model validation will
      # prevent a non-cross repo pull to be created with fork collab allowed.
      return true unless cross_repository?

      # The actor isn't authenticated via an integration, so we can rely on
      # PullRequest model validations to ensure the actor has write access to
      # the head repo.
      return true unless actor.using_auth_via_granular_actor?

      head_repo_contents_writable?
    end

    def disallow?
      !allow?
    end

    private

    def cross_repository?
      head_repository != base_repository
    end

    # Private: Does the programmatic actor have access to the head repo that allows
    # contents write access?
    #
    # Returns a Boolean.
    def head_repo_contents_writable?
      grant = ProgrammaticActor::Grant.with(actor).with_target(head_repository.owner)
      grant && head_repository.resources.contents.writable_by?(grant)
    end
  end
end
