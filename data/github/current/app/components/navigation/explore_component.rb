# typed: true
# frozen_string_literal: true

module Navigation
  class ExploreComponent < ApplicationComponent
    private

    def show_showcase_link?
      GitHub.showcase_enabled?
    end

    def show_activity_link?
      GitHub.enterprise?
    end
  end
end
