# typed: true
# frozen_string_literal: true

module Repositories
  class StarButtonComponent < ApplicationComponent
    extend T::Helpers
    extend T::Sig

    include AnalyticsHelper
    include HydroHelper
    include RepositoryAnalyticsHelper
    include UsersHelper
    include EnterpriseManagedUsersHelper
    include GitHub::Memoizer

    BUTTON_CANT_STAR_LABEL = GitHub::HTMLSafeString.make("You can't star at this time")

    sig { params(repository: Repository).void }
    def initialize(repository:)
      @context = "repository"
      @repository = repository
    end

    private

    sig { returns(String) }
    def unable_to_star_aria_label
      if emu_contribution_blocked?(@repository)
        "You cannot star repositories outside of your enterprise #{enterprise_name}"
      else
        BUTTON_CANT_STAR_LABEL
      end
    end

    memoize def is_starred?
      return @starred if @starred != nil
      @starred = logged_in? && @repository.starred_by?(current_user)
    end
  end
end
