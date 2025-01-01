# typed: true
# frozen_string_literal: true

module Suggestions::RepositoryContextDependency
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  private

  sig { returns(T.nilable(Repository)) }
  memoize def repository_context
    nwo = params[:repo]

    return nil unless nwo

    repo = Repository.with_name_with_owner(nwo)

    unless repo.present? && repo.readable_by?(current_user)
      return nil
    end

    repo
  end

  def resource_for_conditional_access
    repository_context || self
  end

  def target_for_conditional_access
    # The repository object can be nil if the repo param is not present or if the user doesn't have read access
    # to the repository. In these cases, we don't need a TFCA. Limiting this to the index action
    # for added safety if other actions get added in the future.

    if repository_context.nil? && action_name == "index"
      return :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end

    T.must(repository_context).target_for_conditional_access
  end
end
