# typed: strict
# frozen_string_literal: true

module PullRequest::CodeownersDependency
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { PullRequest }

  # A Repository::Codeowners object for the current changed paths.
  #
  # If there's an error determining the changed paths on this pull, the
  # Repository::Codeowners instance will effectively act as a NullObject.
  #
  # Returns a Repository::Codeowners object.
  sig { returns(T.nilable(Repository::Codeowners)) }
  def codeowners # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
    # The "incorrect" memoization pattern is intentional and seemingly load-bearing, given that a number of tests fail
    # when converted to use the GitHub::Memoizer#memoize helper.
    @codeowners ||= T.let(async_codeowners.sync, T.nilable(Repository::Codeowners))
  end

  sig { returns(Promise[T.nilable(Repository::Codeowners)]) }
  def async_codeowners
    promise = async_base_repository.then do |base_repository|
      promises = [
        T.must(base_repository).async_organization,
        T.must(base_repository).async_network
      ]
      promises += [async_stack] if PullRequests::Stacks.enabled?(base_repository)

      Promise.all(promises).then do
        codeowners = Repository::Codeowners.new(base_repository, ref: stack_or_pull_base_ref_name)
        if codeowners.file
          async_changed_paths_for_codeowners.then do |changed_paths|
            codeowners.tap do |codeowners|
              codeowners.paths = changed_paths
            end
          end
        else
          codeowners
        end
      end
    end

    T.unsafe(promise)
  end

  # A Repository::Codeowners object for the current changed paths.
  #
  # @raise [PullRequest::DetermineCodeownersError]
  sig { returns(Repository::Codeowners) }
  def codeowners!
    codeowners.tap do
      raise PullRequest::DetermineCodeownersError.new(@codeowners_paths_load_error) if codeowners_paths_load_error?
    end
  end

  # Find the paths changed by this pull request which may be owned by code owners.
  #
  # Will return an empty Array if the diff can't be loaded.
  #
  # codeowners_paths_load_error? can be used to check whether or not
  # the diff was loaded.
  #
  # Returns an array of String paths.
  sig { returns(T::Array[String]) }
  def changed_paths_for_codeowners
    async_changed_paths_for_codeowners.sync
  end

  # Asynchronously finds the paths changed by this pull request which may be owned by code owners.
  sig { returns(Promise[T::Array[String]]) }
  def async_changed_paths_for_codeowners
    async_historical_comparison.then do |historical_comparison|
      historical_comparison.async_build_diff.then do |diff|
        diff.deltas.flat_map(&:paths).uniq
      end
    end.catch do |error|
      case error
      when GitRPC::ObjectMissing
        @codeowners_paths_load_error = T.let(error, T.nilable(GitRPC::ObjectMissing))
        []
      else
        raise error
      end
    end
  end

  # Can we trust the Repository::Codeowners object for this pull?
  #
  # True if we were able to load the historical diff for codeowners, false
  # if that encountered an error.
  #
  sig { returns(T::Boolean) }
  def codeowners_paths_load_error?
    !!@codeowners_paths_load_error
  end
end
