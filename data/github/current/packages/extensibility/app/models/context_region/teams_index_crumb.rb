# typed: true
# frozen_string_literal: true

module ContextRegion
  class TeamsIndexCrumb < Crumb
    def label
      "Teams"
    end

    def prefix_octicon
      :people
    end

    def path_name
      :teams_path
    end

    def path_args
      [object]
    end

    def parent
      UserCrumb.new(object, **options)
    end
  end
end
