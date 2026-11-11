# typed: true
# frozen_string_literal: true

module Forks
  class ForksHeaderComponent < ApplicationComponent
    sig { returns(PathResolver) }
    attr_reader :path_resolver

    sig { params(path_resolver: PathResolver, render_controls: T::Boolean).void }
    def initialize(path_resolver, render_controls)
      @path_resolver = path_resolver
      @render_controls = render_controls
    end

    private

    def render_controls?
      @render_controls
    end

    sig { returns(String) }
    def tree_view_path
      network_members_path(
        @path_resolver.repo_owner_display_login,
        @path_resolver.repo_name,
      )
    end
  end
end
