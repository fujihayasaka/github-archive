# typed: strict
# frozen_string_literal: true

module Memexes
  module ThisRepositoryDependency
    extend T::Helpers

    extend ActiveSupport::Concern
    include MemexesHelper

    requires_ancestor { ApplicationController }

    sig { params(repository_id: T.nilable(Integer)).returns(T.nilable(Repository)) }
    def this_repository(repository_id: nil)
      return @this_repository if defined?(@this_repository)
      target_repo_id = repository_id || underscored_params[:repository_id]
      @this_repository = T.let(T.cast(Repositories.domain.by_id(target_repo_id.to_i), T.nilable(Repository)), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    end

    sig { void }
    def require_this_repository
      render_404 unless can_read_this_repository?
    end

    sig { returns(T.nilable(T::Boolean)) }
    def can_read_this_repository?
      this_repository&.readable_by?(current_user)
    end

    sig { returns(T::Boolean) }
    def should_require_this_repository?
      action_name == "search_issues_and_pulls" || repository_mode?
    end

    sig { returns(T::Boolean) }
    def repository_mode?
      underscored_params[:repository_id].present?
    end
  end
end
