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

      def password_and_otp_authenticate(login, password, otp)
        user, message = find_user(login)

        unless user
          message ||= "Could not find user"
          return Result.failure message: message
        end

        if user.suspended?
          return Result.suspended_failure message: "User is suspended."
        end

        client = ::Octokit::Client.new(login: user.login, password: password)
        begin
          authorizations = client.authorizations \
            client_id: GitHub.github_oauth_client_id,
            headers: otp_header(otp)
        rescue ::Octokit::OneTimePasswordRequired => e
          # This call will POST /authorizations. This results in a 2FA SMS
          # being sent to the user if they have SMS enabled. The result will
          # come back again with the `X-GitHub-OTP: required;` header,
          # causing Octokit to raise an exception.
          client.create_authorization rescue nil
          return Result.two_factor_failure user, e.password_delivery
        end

        if oauth_authorized?(authorizations)
          Result.success user
        else
          Result.failure message: "not authorized"
        end
      rescue # rubocop:todo Lint/GenericRescue
        Result.failure message: "unknown error"
      end

      def otp_header(otp)
        otp.blank? ? {} : { "X-GitHub-OTP" => otp.to_s }
      end

      # Check if the user has already signed in
      # in this host using OAuth.
      #
      # Although it is unlikely, I could sign in
      # in a different host if a username with my login exists
      # and we don't check this. Which could lead to an identity stealing.
      def oauth_authorized?(authorizations)
        authorizations.present?
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
      # The GitHubOauth provided is special since its ability to do username
      # and password auth depends on whether GitHub.com supports it. Used
      # exclusively in GHES it provides a way for GHES users to sign
      # in using their GitHub.com credentials.
      #
      # As such we have no great way of knowing (other than checking if the
      # current date is post the sunset date) whether this provider can support
      # basic auth so we'll leave it on until after it's definitely been
      # sunset and then flip this.
      def verifiable?
        true
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
