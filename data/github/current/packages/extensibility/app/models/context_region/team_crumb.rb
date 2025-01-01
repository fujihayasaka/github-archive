# typed: true
# frozen_string_literal: true

module ContextRegion
  class TeamCrumb < Crumb
    def label
      object.name
    end

    def prefix_octicon
      :people
    end

    def parent
      if object.parent_team.present?
        TeamCrumb.new(object.parent_team, **options)
      else
        TeamsIndexCrumb.new(object.organization, **options)
      end
    end

    def path_name
      :team_path
    end

    def path_args
      [object]
    end

    def header_navigation_component
      Site::Header::UnderlineNavComponent.new(label: "Team", tabs: Team::NavigationTabs.for(team: object, current_user: options[:current_user]))
    end
  end
end
