# typed: strict
# frozen_string_literal: true

class Statuses::ReviewStatusProtectionWarningComponent < ApplicationComponent
  extend T::Sig

  sig { params(pull: PullRequest, current_user: User).void }
  def initialize(pull:, current_user:)
    @pull = pull
    @current_user = current_user
    @repository = T.let(@pull.repository, T.nilable(Repository))
    @repository_owner = T.let(@repository&.owner, T.nilable(User))
  end

  sig { returns(T::Boolean) }
  memoize def ruleset_protected?
    return false unless @repository
    @repository.rulesets_for_ref("refs/heads/#{@pull.base_ref}").any?
  end

  sig { returns(T::Boolean) }
  memoize def branch_protected?
    return false unless @repository
    @repository.branch_protected?(@pull.base_ref)
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless @repository
    return false if @repository.supports_protected_branches?
    return false unless @repository_owner
    return false unless @repository_owner.organization? || (!@repository_owner.organization? && @repository.adminable_by?(@current_user))
    branch_protected? || ruleset_protected?
  end

  sig { returns(T.nilable(MemberFeatureRequest::Feature)) }
  def get_feature
    return MemberFeatureRequest::Feature::Rulesets if ruleset_protected?
    MemberFeatureRequest::Feature::ProtectedBranches
  end
end
