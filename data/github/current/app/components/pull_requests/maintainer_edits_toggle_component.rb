# typed: strict
# frozen_string_literal: true

module PullRequests
  class MaintainerEditsToggleComponent < ApplicationComponent
    extend T::Sig
    include GitHub::Memoizer

    sig do
      params(
        pull_request: PullRequest,
        base_repository: Repository,
        head_repository: Repository,
        include_form: T::Boolean,
      ).void
    end
    def initialize(pull_request:, base_repository:, head_repository:, include_form:)
      @pull_request    = pull_request
      @base_repository = base_repository
      @head_repository = head_repository
      @include_form    = include_form
    end

    private

    sig { returns(PullRequest) }
    attr_reader :pull_request

    sig { returns(Repository) }
    attr_reader :base_repository

    sig { returns(Repository) }
    attr_reader :head_repository

    sig { returns(T::Boolean) }
    def render?
      return false if base_repository == head_repository
      return false unless head_repository.pushable_by?(current_user)

      head_owner = head_repository.owner
      head_owner.present? && head_owner.user?
    end

    sig { returns(T::Boolean) }
    def include_form?
      @include_form
    end

    sig { returns(T::Boolean) }
    memoize def checked?
      return true if pull_request.new_record?
      pull_request.fork_collab_granted?
    end

    sig { returns(T::Boolean) }
    memoize def exposes_secrets?
      head_repository.actions_app_installed?
    end

    sig { returns(String) }
    def label
      if exposes_secrets?
        "Allow edits and access to secrets by maintainers"
      else
        "Allow edits by maintainers"
      end
    end
  end
end
