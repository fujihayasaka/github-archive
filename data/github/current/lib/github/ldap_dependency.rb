# typed: true
# frozen_string_literal: true

module GitHub
  module LDAP
    require "github/ldap" # this loads classes from github-ldap gem.

    autoload :Authorization, "github/ldap/authorization"
    autoload :Instrumentable, "github/ldap/instrumentable"
    autoload :NewMemberSync, "github/ldap/new_member_sync"
    autoload :Search, "github/ldap/search"
    autoload :TeamSync, "github/ldap/team_sync"
    autoload :UserSync, "github/ldap/user_sync"

    def self.debug_logging_enabled?
      GitHub.cache.fetch("ldap.debug_logging_enabled", ttl: 1.minute) do
        GitHub.config.get("ldap.debug_logging_enabled") == "true"
      end
    end

    def self.search
      @search ||= Search.new
    end
  end
end
