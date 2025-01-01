# typed: true
# frozen_string_literal: true

module GitHub
  module FeatureFlag
    include Kernel

    EMPLOYEES_ORG_AND_TEAM_NAME = %w[github employees].freeze
    BOUNTY_HUNTERS_ORG_AND_TEAM_NAME = %w[GitHubBounty bounty-hunters].freeze
    CAMPUS_EXPERTS_BADGE_ORG_AND_TEAM_NAME = %w[campus-experts campus-experts-badge].freeze
    GITHUB_STARS_ORG_AND_TEAM_NAME = %w[GitHub-Stars stars].freeze
    GITHUB_DEVELOPER_RELATIONS_TEAM_NAME  = %w[github devrel].freeze

    # Regexes to match all known usages of FlipperFeatures
    # If a new method or usage pattern is added, please add a regex for it here,
    # and a matching example to test/fixtures/feature_flags/file_a.
    FLIPPER_USAGE_PATTERNS = [
      /GitHub\.flipper\[["':](\w+)"?'?\]/,
      /GitHub::flipper\[["':](\w+)"?'?\]/,
      /GitHub\.flipper\.enable\(["':](\w+).*\)/,
      /GitHub\.flipper\.disable\(["':](\w+).*\)/,
      /GitHub\.flipper\.enabled\?\(["':](\w+).*\)/,
      /GitHub\.flipper\.feature\(:(\w+).*\)/,
      /feature_enabled\?[\( ]["':](\w+)/,
      /\.try\(:feature_enabled\?, ["':](\w+)"?'?\)/,
      /feature_flag\s["':](\w+)"?'?$/,              # feature_flag :some_flag[EOL] or feature_flag "some_flag"[EOL] or feature_flag 'some_flag'[EOL]
      /feature_flag\s["':](\w+)"?'?\s/,             # feature_flag :some_flag[whitespace] or feature_flag "some_flag"[whitespace] or feature_flag 'some_flag'[whitespace]
      /feature_flag\s["':](\w+)"?'?[\s,]\s[^:'"]/, # feature_flag :some_flag, some_other_arg or feature_flag "some_flag", some_other_arg or feature_flag 'some_flag', some_other_arg
      /feature_flag[\( ]:\w+,\s["':](\w+)/, # feature_flag :not_a_flag, :some_flag or feature_flag :not_a_flag, "some_flag" or feature_flag :not_a_flag, 'some_flag'
      /self\.feature_flag\s?=\s?["':](\w+)/, # self.feature_flag = :some_flag (from slash commands)
      /feature_enabled_globally_or_for_current_user\?[\(\s]?["':](\w+)"?'?\)?/,
      /feature_enabled_globally_or_for_current_user_or_entity\?[\(\s]?["':](\w+)"?'?\)?/,
      /feature_enabled_for_current_user\?[\(\s]feature_name:\s?["':](\w+).*\)/,
      /feature_enabled_for_current_visitor\?[\(\s]feature_name:\s?["':](\w+)"?'?\)/,
      /feature_enabled_globally_or_for_user\?[\(\s]feature_name:\s?["':](\w+).*\)?/,
      /feature_enabled_for_user_or_current_visitor\?[\(\s]feature_name:\s?["':](\w+).*\)?/,
      /feature_enabled_for_source\?[\(\s]?["':](\w+)"?'?\)?/, # feature_enabled_for_source?(:some_flag)
      /feature_enabled_via_current_visitor\?[\(\s]?["':](\w+)"?'?\)?/, # feature_enabled_via_current_visitor?(:some_flag)
      /emu_feature_enabled\?[\(\s]feature_name:\s?["':](\w+).*,\ssubject:\s?.+\)?/,
      /feature_preview_enabled\?\(["':](\w+)/,
      /feature_flag_enabled\?\(\w+,\s["':](\w+)"?'?\)/, # feature_flag_enabled?(:not_a_flag, :some_flag)
      /@featureFlagged\(flag:\s"(\w+)"/,
      /feature_enabled_for_repo_or_org[\(\s]?["':](\w+)"?'?\)?/,
      /feature_enabled_for_repo_or_owner\?[\(\s]?["':](\w+)"?'?\)?/,
      /check_enabled_and_disabled_flags\?[\(\s]?["':](\w+)["']?,\s["':](\w+)["']?\)?/, # check_enabled_and_disabled_flags?(:some_enablement_flag, :some_disablement_flag)
      /async_scoped_feature_flag_enabled\?[\(\s]?["':](\w+)["']?\)?/, # async_scoped_feature_flag_enabled?(:some_flag)
      /flag_enabled_for_entity_or_parent\?\([^,]+,\s*["':](\w+)["']?\)/, # flag_enabled_for_entity_or_parent?(entity, :some_flag)
    ].freeze

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

    # Internal: Loads and memoizes the Shopify org.
    #
    # Returns an org or false if it doesn't exist.
    def shopify_org
      org_cache["shopify"]
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

    # Internal: Checks to see if the User has access to the Organization.
    #
    # org_name - The symbol name of the org.
    # user     - The User.
    #
    # Returns a Boolean.
    def user_org_access?(org_name, user)
      org = org_cache[org_name.to_s]

      return false unless org

      ActiveRecord::Base.connected_to(role: :reading) do
        Ability.unscoped do
          GitHub.dogstats.distribution_time("feature_flags.orgs.member_check_latency", tags: ["org_name:#{org_name}"]) do
            org.member?(user)
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

    # Cached org-name to Organization object mapping.
    #
    # Accessing this Hash will lookup and cache organization.
    #
    # Returns a Hash.
    def org_cache
      @org_cache ||= Hash.new do |hash, org_name|
        hash[org_name] = begin
          if GitHub.multi_tenant_enterprise?
            false
          else
            ActiveRecord::Base.connected_to(role: :reading) do
              Organization.unscoped do
                GitHub.dogstats.distribution_time("feature_flags.groups.org_cache_latency", tags: ["org_name:#{org_name}"]) do
                  Organization.find_by_login(org_name) || false
                end
              end
            end
          end
        end
      end
    end

    extend self
  end
end
