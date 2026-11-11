# typed: true
# frozen_string_literal: true

class ContentAuthorizer::DiscussionCommentAuthorizer < ContentAuthorizer
  attr_accessor :discussion, :repo

  sig { params(actor: T.untyped, operation: T.untyped, data: T.untyped).void }
  def initialize(actor, operation, data)
    super
    @discussion = data[:discussion] || GitHub::NullDiscussion.new
    @repo = data[:repo] || GitHub::NullRepository.new
  end

  # Public: All of the authorization errors blocking the given actor from
  # creating or mutating a discussion comment. These should be assembled in
  # priority order (from most urgent/important to least) because the API
  # will only return the first error discovered.
  #
  # fail_fast - Bail out after the first failure.
  #
  # Returns an Array of ContentAuthorizationError objects.
  sig { params(fail_fast: T.untyped).returns(T.untyped) }
  def errors(fail_fast: false)
    ([]).tap do |errors|
      if actor.must_verify_email? && verified_email_required_to?(operation)
        errors << ContentAuthorizationError::EmailVerificationRequired.new
        return errors if fail_fast
      end

      if repo.archived?
        errors << ContentAuthorizationError::RepoArchived.new
        return errors if fail_fast
      end

      staff_is_minimizing = actor.site_admin? && GitHub.context[:staff_minimizing]
      if !staff_is_minimizing && discussion.locked_for?(actor)
        errors << ContentAuthorizationError::DiscussionLocked.new
        return errors if fail_fast
      end

      if !in_automated_data_transformation? && repo.locked_on_migration?
        errors << ContentAuthorizationError::RepoLocked.new
        return errors if fail_fast
      end
    end
  end
end
