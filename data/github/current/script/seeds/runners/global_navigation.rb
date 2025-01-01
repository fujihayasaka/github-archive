# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class GlobalNavigation < Seeds::Runner
      def self.help
        <<~HELP
        Seeds objects needed for developing and testing the global navigation.
        HELP
      end

      def self.run(options = {})
        self.enable_features
        # nested teams are a great way to test pages with many levels of context region breadcrumbs
        self.create_nested_teams
      end

      def self.enable_features
        puts "Enabling feature flags..."

        features = ["responsive_context_region"]
        features.each do |feature|
          Seeds::Objects::FeatureFlag.enable(feature_flag: feature, actor: User.find_by_login("monalisa"))
        end
      end

      def self.create_nested_teams
        puts "Creating nested teams..."
        org = Organization.find_by_login("github")
        owner = User.find_by_login("monalisa")

        teams_to_create = [
          "Developers",
          "Core Productivity",
          "Core UX",
          "Search & Navigation",
          "Code Reviewers",
          "global-navigation-reviewers",
        ]

        previous_team = T.let(nil, T.nilable(Team))

        teams_to_create.each do |team_name|
          slug = team_name.parameterize

          team = Team.find_or_create_by!(slug: slug, organization: org) do |t|
            t.name = team_name
            t.description = "It's the #{team_name} team"
            t.privacy = "closed"
          end

          if previous_team
            team.parent_team_id = previous_team.id
          end

          team.save!

          team.add_member(owner)
          previous_team = T.let(team, T.nilable(Team))
        end

        # team pages are unfortunately not all responsive, but the projects page is, so that's where we can link to
        puts "Created #{teams_to_create.size} teams with nested navigation breadcrumbs, visit http://github.localhost/orgs/github/teams/#{T.must(previous_team).slug}/projects to start testing"
      end
    end
  end
end
