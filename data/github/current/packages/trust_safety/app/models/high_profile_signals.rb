# typed: true
# frozen_string_literal: true

# High Profile entities are defined by the following Trust & Safety criteria:
# https://github.com/github/trust-safety/blob/main/docs/operations/escalation-procedures/high-profile-escalation.md
module HighProfileSignals
  extend self

  ORG_ADMINS_THRESHOLD = 5
  ORG_MEMBERS_THRESHOLD = 25
  REPO_CONTRIBUTORS_THRESHOLD = 10
  REPO_FORKS_THRESHOLD = 50
  REPO_WATCHERS_THRESHOLD = 100
  USER_FOLLOWERS_THRESHOLD = 100

  sig { params(repo: Repository).returns(T.nilable([T::Boolean, String])) }
  def high_profile_repo?(repo)
    return if repo.private?

    high_profile_criteria = []

    result = Platform::Loaders::Dependencies.load_packages({
      package_filter: {
        repository_id: repo.id,
        first: 1,
        package_id: repo.used_by_package_id,
        preview: repo.dependency_graph_preview?,
      },
      dependents_filter: {
        type: :repository,
        first: 8,
      },
      include_dependents: true,
    }).sync

    package = result.ok? ? result.value!.first : nil

    repository_dependents_count = package&.repository_dependents_count || 0
    package_dependents_count = package&.dependents&.count || 0

    has_dependents = (repository_dependents_count + package_dependents_count) > 0

    high_profile_criteria << "forks count" if repo.forks_count >= REPO_FORKS_THRESHOLD
    high_profile_criteria << "watchers count" if repo.watchers_count >= REPO_WATCHERS_THRESHOLD
    high_profile_criteria << "contributors count" if CommitContributions.domain.contributors_count_for_repository(repo) >= REPO_CONTRIBUTORS_THRESHOLD
    high_profile_criteria << "has dependents" if has_dependents

    owner_trust_tier = get_trust_tier_for_repo_owner(repo)
    owner_trust_reason = owner_trust_tier&.verbose_reason
    high_profile_criteria << "repository owner has trusted tier due to: #{owner_trust_reason}" if owner_trust_tier&.tier == TrustTiers::Tier::TRUSTED

    if high_profile_criteria.any?
      [true, "Repository meets criteria threshold: #{high_profile_criteria.join(", ")}"]
    end
  end

  sig { params(user: User).returns(T.nilable([T::Boolean, String])) }
  def high_profile_user?(user)
    high_profile_criteria = []

    if user.is_a?(Organization)
      high_profile_criteria << "member count" if user.member_count >= ORG_MEMBERS_THRESHOLD
      high_profile_criteria << "admin count" if user.admins.size >= ORG_ADMINS_THRESHOLD
    else
      high_profile_criteria << "follower count" if user.followers_count! >= USER_FOLLOWERS_THRESHOLD
    end
    high_profile_criteria << "owns one or more high profile repositories" if owns_high_profile_repo?(user)

    user_trust_tier = get_trust_tier_for_user(user)
    user_trust_reason = user_trust_tier&.verbose_reason
    high_profile_criteria << "has trusted tier status due to: #{user_trust_reason}" if user_trust_tier&.tier == TrustTiers::Tier::TRUSTED

    if high_profile_criteria.any?
      [true, "#{user.class.name} meets criteria threshold: #{high_profile_criteria.join(", ")}"]
    end
  end

  private

  sig { params(user: User).returns(T::Boolean) }
  def owns_high_profile_repo?(user)
    user.public_repositories.exists?(["public_fork_count >= ? OR watcher_count >= ?", REPO_FORKS_THRESHOLD, REPO_WATCHERS_THRESHOLD])
  end

  sig { params(repo: Repository).returns(T.nilable(TrustTiers::TierResult)) }
  def get_trust_tier_for_repo_owner(repo)
    TrustTiers::Tier.for_repository(repo, "high_profile_signals")
  rescue StandardError => e
    GitHub.logger.warn(
      "code.namespace" => "HighProfileSignals",
      "code.function" => "get_trust_tier_for_repo_owner",
      "gh.repo.id" => repo.id,
      "error" => e.message
    )
    nil
  end

  sig { params(user: User).returns(T.nilable(TrustTiers::TierResult)) }
  def get_trust_tier_for_user(user)
    TrustTiers::Tier.for_billable_owner(user, "high_profile_signals")
  rescue StandardError => e
    GitHub.logger.warn(
      "code.namespace" => "HighProfileSignals",
      "code.function" => "get_trust_tier_for_user",
      "gh.user.id" => user.id,
      "gh.user.type" => user.class.name,
      "error" => e.message
    )
    nil
  end
end
