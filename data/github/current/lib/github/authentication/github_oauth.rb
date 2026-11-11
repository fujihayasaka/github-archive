# typed: true
# frozen_string_literal: true

module GitHub
  module Authentication
    require "octokit"

    # Authentication provided for GHES which lets Enterprise users sign
    # in using their GitHub.com credentials through the GitHub.com API.
    #
    # This feature was deprecated and removed as an option for new GHES
    # installations in November of 2015 (and in GHES 2.3), see:
    #
    # https://github.com/github/enterprise2/pull/4238
    # https://docs.github.com/enterprise/2.2/admin/guides/user-management/using-github-oauth
    class GitHubOauth < OmniAuth
      # The /authorizations API this method relied on was removed from
      # GitHub.com, and the Octokit methods (authorizations,
      # create_authorization) no longer exist in Octokit 5+. This auth
      # provider has been deprecated since GHES 2.3 (~2015). Password-based
      # authentication always fails; the OAuth web flow still works.
      def password_and_otp_authenticate(_login, _password, _otp)
        Result.failure message: "GitHub OAuth password authentication is no longer supported"
      end

      def strategy
        Strategy
      end

      def config
        {
          client_id: GitHub.github_oauth_client_id,
          client_secret: GitHub.github_oauth_secret_key,
          github_organization: GitHub.github_oauth_organization,
          organization_team: GitHub.github_oauth_team,
        }
      end

      def name
        "GitHub OAuth"
      end

      def create_user(uid, user_info)
        user = super(uid, user_info)

        user_info.copy_profile(user)
        user_info.add_emails(user)
        user_info.add_public_keys(user)
        add_to_organization(user)

        user
      end

      def add_to_organization(user)
        org_name, team_id = config[:github_organization].split("/").first, nil

        if config[:organization_team]
          org_name, team_id = config[:organization_team].split("/")
        end

        if team_id && org = Organization.find_by_login(org_name)
          if team = org.teams.find_by_slug(team_id)
            team.add_member(user)
          end
        end
      end

      # Whether or not to validate a user
      #
      # This is used in the /meta API endpoint in order to signal to our
      # client apps (like Desktop) whether they will be able to authenticate
      # using username and password or if they have to use the oauth web flow
      # for sign in.
      #
      # Password-based authentication via the Octokit /authorizations API
      # was removed upstream, so this provider can no longer verify
      # credentials. Clients must use the OAuth web flow.
      def verifiable?
        false
      end

      def sudo_mode_enabled?(user)
        false
      end

      def rails_logout(request, current_user, redirect_to: "dashboard")
        LogoutResult.success File.join(GitHub.url, redirect_to)
      end
    end

    require "github/authentication/github_oauth/strategy"
    require "github/authentication/github_oauth/user_info"
  end
end
