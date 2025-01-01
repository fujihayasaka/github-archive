# typed: strict
# frozen_string_literal: true

module ContextRegion
  class TeamCrumb < Crumb
    sig { override.returns(String) }
    def label
      object.name
    end

    sig { override.returns(Symbol) }
    def prefix_octicon
      :people
    end

    sig { override.returns(Crumb) }
    def parent
      if object.parent_team.present?
        TeamCrumb.new(object.parent_team)
      else
        TeamsIndexCrumb.new(object.organization)
      end
    end

    sig { override.returns(T.nilable(Symbol)) }
    def path_name
      :team_path
    end

    sig { override.returns(T::Array[T.untyped]) }
    def path_args
      [object]
    end

    sig { override.returns(Site::Header::UnderlineNavComponent) }
    def header_navigation_component
      Site::Header::UnderlineNavComponent.new(label: "Team", tabs: Team::NavigationTabs.for(team: object, current_user: options[:current_user]))
    end
  end
end
