# typed: strict
# frozen_string_literal: true

class PullRequestCreationConfig
  include Configurable::PullRequestCreationPolicy
  include Configurable::PullRequestCreationCap
  include Configurable::PullRequestCreationCapBypass

  CapSubject = T.type_alias { T.nilable(T.any(Ability::Actor, GitHub::NullUser)) }

  # Provides the PullRequestCopilotAttribution-shaped interface needed before a PR exists.
  class CopilotAttributionAttributes < T::Struct
    const :user, User
  end

  # Provides the PullRequest-shaped interface used by cap checks before a PR exists.
  class PullRequestAttributes < T::Struct
    const :user, T.nilable(User)
    const :draft, T::Boolean
    const :pull_request_copilot_attributions,
      T::Array[CopilotAttributionAttributes],
      factory: -> { [] }

    sig { returns(T::Boolean) }
    def draft?
      draft
    end
  end

  # BP configurables are currently stored associated with a repository
  sig { returns(String) }
  def configuration_entry_type
    "Repository"
  end

  # Override to avoid base `configuration_entry_id` from requiring `ApplicationRecord::Base` ancestry
  sig { returns(Integer) }
  def configuration_entry_id
    T.must(repository.id)
  end

  # Leverage the repository's cached config
  sig { returns(Configuration) }
  def config
    T.cast(repository, Repository).config # rubocop:todo GitHub/AvoidCast
  end

  # Internal: Get the configuration owner.
  # values for a Repository can be cascaded from (or overridden by) the repo owner
  sig { returns(T.nilable(Users::IUser)) }
  def configuration_owner
    repository.owner
  end

  # Internal: Get the configuration owner asynchronously.
  # values for a Repository can be cascaded from (or overridden by) the repo owner
  sig { returns(Promise[T.nilable(Users::IUser)]) }
  def async_configuration_owner
    repository.async_owner
  end

  sig { returns(Repositories::IRepository) }
  attr_reader :repository

  sig { params(repository: Repositories::IRepository).void }
  def initialize(repository)
    @repository = repository
  end

  sig { params(user: CapSubject).returns(T::Boolean) }
  def pull_request_creation_cap_applicable_to_user?(user)
    return false unless pull_request_creation_cap_enabled?
    repo = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast
    return false unless user.is_a?(User) && !user.is_a?(Bot) && !repo.pushable_by?(user)
    return false if pull_request_creation_cap_bypassed?(user:)

    true
  end

  # Return the number of additional PRs the user can open before reaching the cap, or
  # return nil if they're exempt from the cap, if there isn't a cap, or if the cap can't be determined.
  sig { params(user: CapSubject).returns(T.nilable(Integer)) }
  def limit_for_user(user)
    repo = T.cast(repository, Repository) # rubocop:todo GitHub/AvoidCast
    begin
      return nil unless pull_request_creation_cap_applicable_to_user?(user)
      return nil unless user.is_a?(User)

      cap = pull_request_creation_cap
      open_pull_request_count = open_pull_request_count_for_user(user, repo, cap)

      [cap - open_pull_request_count, 0].max
    # Fail open if database, key-value store, permission, or request time budget checks fail
    rescue *GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST => exception
      Failbot.report!(
        exception,
        {
          "code.namespace" => "PullRequestCreationConfig",
          "code.function" => "limit_for_user",
          "gh.repo.id" => repo.id,
        },
      )
      nil
    end
  end

  # Return true if the user has reached the cap and can't open additional PRs, or
  # return false if they haven't reached the cap, if they're exempt from the cap, if there isn't a cap, or if the cap can't be determined.
  sig { params(user: CapSubject).returns(T::Boolean) }
  def limit_reached_for_user?(user)
    limit_for_user(user) == 0
  end

  sig { params(pull_request: T.any(PullRequest, PullRequestAttributes)).returns(T::Boolean) }
  def pull_request_exceeds_limit?(pull_request)
    return false if pull_request.draft?

    user = pull_request.pull_request_copilot_attributions.first&.user || pull_request.user

    limit_reached_for_user?(user)
  end

  private

  # Count non-draft open PRs authored-by or attributed-to the user (includes Copilot-generated PRs).
  # Applies a LIMIT so we never scan more rows than needed to determine whether
  # the cap has been reached.
  sig { params(user: User, repo: Repository, cap: Integer).returns(Integer) }
  def open_pull_request_count_for_user(user, repo, cap)
    @open_pull_request_count_cache = T.let(
      @open_pull_request_count_cache,
      T.nilable(T::Hash[Integer, Integer])
    )
    @open_pull_request_count_cache ||= {}
    cached = @open_pull_request_count_cache[user.id]
    return cached unless cached.nil?

    @open_pull_request_count_cache[user.id] = GitHub.dogstats.distribution_time("pull_requests.creation_config.open_pull_request_count.duration") do
      # Keep each SQL query within a single domain. Load Copilot attribution IDs
      # separately, then count the open attributed PRs that were not already
      # counted as authored by the user.
      open_pull_requests = repo.pull_requests.where(status: "open", work_in_progress: false)
      authored_open_pull_request_count = open_pull_requests.for_user(user).limit(cap).count

      next authored_open_pull_request_count if authored_open_pull_request_count >= cap

      remaining_limit = cap - authored_open_pull_request_count
      # No limit on this pluck: the attribution table is scoped to a single
      # user+repo so the result set is inherently small, and limiting here could
      # cause undercounts when stale attributions (closed/draft PRs) are returned
      # before valid ones.
      copilot_attributed_pull_request_ids = PullRequestCopilotAttribution
        .where(repository_id: repo.id, user_id: user.id)
        .pluck(:pull_request_id)

      attributed_open_pull_request_count = 0
      if copilot_attributed_pull_request_ids.any?
        attributed_open_pull_request_count = open_pull_requests
          .where(id: copilot_attributed_pull_request_ids)
          .where.not(user_id: user.id)
          .limit(remaining_limit)
          .count
      end

      authored_open_pull_request_count + attributed_open_pull_request_count
    end
  end
end
