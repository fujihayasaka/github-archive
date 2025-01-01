# typed: true
# frozen_string_literal: true

module ControllerMethods
  module Codespaces
    extend T::Helpers
    extend ActiveSupport::Concern

    requires_ancestor { ApplicationController }

    included do
      T.bind(self, T.class_of(ApplicationController))
      helper_method :codespaces_menu_visibility
    end

    def codespaces_menu_visibility
      return @codespaces_menu_visibility if @codespaces_menu_visibility

      repo_policy = if logged_in?
        repository = @pull&.head_repository || current_repository
        ::Codespaces::RepositoryPolicy.async_with_prefill(current_user, repository, pull_request: @pull).sync
      end

      @codespaces_menu_visibility = ::Codespaces::MenuVisibility.new(
        user: current_user,
        repository_policy: repo_policy,
        pull_request: @pull,
      )
    end
  end
end
