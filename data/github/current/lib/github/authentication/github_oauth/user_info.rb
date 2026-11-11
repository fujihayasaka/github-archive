# typed: true
# frozen_string_literal: true

module GitHub
  module Authentication
    class GitHubOauth
      class UserInfo
        ATTRIBUTES = %w[id login name email company blog location].freeze

        attr_accessor :attribs, :token

        def initialize(attribs = nil, token = nil)
          @attribs = attribs
          @token   = token
        end

        def self.load(access_token)
          api = ::Octokit::Client.new(access_token: access_token, user_agent: "GitHub Enterprise")
          data = Hash.new

          # normalize everything to strings
          api.user.to_hash.select { |k, _| ATTRIBUTES.include?(k.to_s) }. each do |key, value|
            data[key.to_s] = value
          end

          new(data, access_token)
        end

        def marshal_dump
          Hash[T.unsafe(self).members.zip(T.unsafe(self).values)]
        end

        def marshal_load(hash)
          hash.each { |k, v| send("#{k}=", v) }
        end

        ATTRIBUTES.each do |name|
          define_method(name) { T.unsafe(self).attribs[name] }
        end

        def authorized?(restricted_access)
          org, team = restricted_access.split("/")

          member = api.organization_member?(org, T.unsafe(self).login)
          member = api.team_member?(team, T.unsafe(self).login) if member && team
          member
        end

        def add_public_keys(user)
          keys = api.user.keys || []

          keys.each do |data|
            user.public_keys.create_with_verification \
              title: data["title"],
              key: data["key"],
              verifier: user
          end
        end

        def add_emails(user)
          emails = api.emails(accept: "application/vnd.github.v3")

          emails.each do |data|
            user.add_email(data["email"], is_primary: data["primary"])
          end
          user.set_initial_gravatar_email
        end

        def copy_profile(user)
          attrs = attribs.slice("name", "email", "company", "blog", "location")
          user.create_profile.update(attrs)
        end

        # Access the GitHub API from Octokit
        #
        # Octokit is a robust client library for the GitHub API
        # https://github.com/pengwynn/octokit
        #
        # Returns a cached client object for easy use
        def api
          # Don't cache instance for now because of a ruby marshaling bug present
          # in MRI 1.9.3 (Bug #7627) that causes instance variables to be
          # marshaled even when explicitly specifying #marshal_dump.
          Octokit::Client.new(login: T.unsafe(self).login, access_token: token, user_agent: "GitHub Enterprise")
        end
      end

    end
  end
end
