# typed: strict
# frozen_string_literal: true

module Memexes
  module ThisRepositoryDependency
    extend T::Sig
    extend T::Helpers

    extend ActiveSupport::Concern
    include MemexesHelper

    requires_ancestor { ApplicationController }

    sig { params(repository_id: T.nilable(Integer)).returns(T.nilable(Repository)) }
    def this_repository(repository_id: nil)
      return @this_repository if defined?(@this_repository)
      target_repo_id = repository_id || underscored_params[:repository_id]
      @this_repository = T.let(Repository.find_by(id: target_repo_id), T.nilable(Repository))
    end

    sig { void }
    def require_this_repository
      render_404 unless can_read_this_repository?
    end

    sig { returns(T.nilable(T::Boolean)) }
    def can_read_this_repository?
      this_repository&.readable_by?(current_user)
    end
  end
end
