# typed: true
# frozen_string_literal: true

module FeatureFlag
  include Kernel

  EMPLOYEES_ORG_AND_TEAM_NAME = %w[github employees].freeze
  BOUNTY_HUNTERS_ORG_AND_TEAM_NAME = %w[GitHubBounty bounty-hunters].freeze
  CAMPUS_EXPERTS_BADGE_ORG_AND_TEAM_NAME = %w[campus-experts campus-experts-badge].freeze
  GITHUB_STARS_ORG_AND_TEAM_NAME = %w[GitHub-Stars stars].freeze
  GITHUB_DEVELOPER_RELATIONS_TEAM_NAME  = %w[github devrel].freeze

  # Internal: Loads and memoizes the GitHub Employees Team.
  #
  # Returns a Team or false if it doesn't exist.
  def employees_team
    team_cache[EMPLOYEES_ORG_AND_TEAM_NAME]
  end

  # Internal: Loads and memoizes the @GitHubBounty/bounty-hunters team.
  #
  # Returns a Team or false if it doesn't exist.
  def bounty_hunters_team
    team_cache[BOUNTY_HUNTERS_ORG_AND_TEAM_NAME]
  end

  # Internal: Loads and memoizes the campus-experts/campus-experts-badge team.
  #
  # Returns a Team or false if it doesn't exist.
  def campus_experts_badge_team
    team_cache[CAMPUS_EXPERTS_BADGE_ORG_AND_TEAM_NAME]
  end

  # Internal: Loads and memoizes the github-stars/stars team.
  #
  # Returns a Team or false if it doesn't exist.
  def github_stars_team
    team_cache[GITHUB_STARS_ORG_AND_TEAM_NAME]
  end

  # Internal: Loads and memoizes the github/devrel team.
  #
  # Returns a Team or false if it doesn't exist.
  def github_developer_relations_team
    team_cache[GITHUB_DEVELOPER_RELATIONS_TEAM_NAME]
  end

  # Internal: Loads and memoizes the GitHub Abilities Team.
  #
  # Returns a Team or false if it doesn't exist.
  def abilities_team
    team_cache[%w[github abilities]]
  end

  # Internal: Loads and memoizes the Stafftools Team.
  #
  # Returns a Team or false if it doesn't exist.
  def stafftools_team
    team_cache[%w[github stafftools]]
  end

  def staffship_optout_team
    team_cache[%w[github staffship-features-optout]]
  end

  # Internal: Loads and memoizes the User Security Team.
  #
  # Returns a Team or false if it doesn't exist.
  def user_security_team
    team_cache[%w[github user-security]]
  end

  # Internal: Loads and memoizes the obscured GitHub Enterprise Preview Features team.
  #
  # Returns a Team or false if it doesn't exist.
  def enterprise_preview_features_team
    team_cache[%w[github sekret-enterprise-features-Gvr6pqN]]
  end

  # Internal: Loads and memoizes the Maintainers program features early access team.
  #
  # Returns a Team or false if it doesn't exist.
  def maintainers_early_access_team
    team_cache[%w[maintainers early-access]]
  end

  # Internal: Loads and memoizes the Project Moonstar features early access team.
  #
  # Returns a Team or false if it doesn't exist.
  def integrators_early_access_team
    team_cache[%w[project-moonstar all-integrators]]
  end

  # Internal: Loads and memoizes the stacks contributors.
  #
  # Returns a Team or false if it doesn't exist.
  def stacks_contributors_team
    team_cache[%w[github-stacks stacks_contributors]]
  end

  # Internal: Loads and memoizes the azure stacks collaborators.
  #
  # Returns a Team or false if it doesn't exist.
  def azure_stacks_collaborators_team
    team_cache[%w[github-stacks azure-stacks-collaborators]]
  end

  # Internal: Loads and memoizes the Interns team.
  #
  # Returns a Team or false if it doesn't exist.
  def interns_team
    team_cache[%w[github interns]]
  end

  # Internal: Loads and memoizes the team of folks who can use SIRE.
  #
  # Returns a Team or false if it doesn't exist.
  def sire_team
    team_cache[%w[github sire-hubbers]]
  end

  # Internal: Loads and memoizes the Microsoft everyone team.
  #
  # Returns a Team or false if it doesn't exist.
  def microsoft_team
    team_cache[%w[microsoft everyone]]
  end

  # Internal: Loads and memoizes the Code Intelligence preview team.
  #
  # Returns a Team or false if it doesn't exist.
  def code_intelligence_previews_team
    team_cache[%w[github code-intelligence-previews]]
  end

  # Internal: Checks to see if the User has access to the Team.
  #
  # team_name - The Symbol name of the team. There should be a coresponding
  #             `#{team_name}_team` method in this module.
  # user      - The User.
  #
  # Returns a Boolean.
  def user_team_access?(team_name, user)
    return false unless team = send("#{team_name}_team")

    ActiveRecord::Base.connected_to(role: :reading) do
      Ability.unscoped do
        GitHub.dogstats.distribution_time("feature_flags.groups.member_check_latency", tags: ["team_name:#{team_name}"]) do
          team.member?(user)
        end
      end
    end
  end

  # Cached org-name/team-name to Team object mapping.
  #
  # Accessing this Hash will lookup and cache teams.
  #
  # Eg. `team_cache[["github", "employees"]]` will lookup and cache the
  # @github/employees team. False will be returned if the team doesn't exist.
  #
  # This cache can be cleared like a normal Hash.
  #
  # Eg. `team_cache.clear` will clear cached entries.
  #
  # Returns a Hash.
  def team_cache
    @team_cache ||= Hash.new do |hash, (org_name, team_slug)|
      hash[[org_name, team_slug]] = begin
        if GitHub.multi_tenant_enterprise?
          false
        else
          ActiveRecord::Base.connected_to(role: :reading) do
            Organization.unscoped do
              Team.unscoped do
                GitHub.dogstats.distribution_time("feature_flags.groups.team_cache_latency", tags: ["org_name:#{org_name}", "team_slug:#{team_slug}"]) do
                  org = Organization.find_by_login(org_name)
                  team = org.teams.find_by_slug(team_slug) if org

                  team || false
                end
              end
            end
          end
        end
      end
    end
  end

  extend self
end
