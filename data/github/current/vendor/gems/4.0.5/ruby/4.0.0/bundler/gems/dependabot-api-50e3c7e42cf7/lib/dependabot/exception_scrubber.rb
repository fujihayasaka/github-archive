# frozen_string_literal: true

module Dependabot
  module ExceptionScrubber
    PROXIMA_INTERNAL_HOSTNAME_PATTERN = /unicorn-internal-api\.github-[^.]*\.svc\.cluster\.local/

    NWO_PATH_PATTERN = %r{(?<owner>[\w.-]+)/(?<name>[\w.-]+)}
    REPO_NWO_PATTERN_CLOUD =
      %r{
        api\.github\.com/repos/#{NWO_PATH_PATTERN}|
        (?<!\.)github\.com/#{NWO_PATH_PATTERN}|
        internal-api\.service\.iad\.github\.net/repos/#{NWO_PATH_PATTERN}
      }x
    REPO_NWO_PATTERN_PROXIMA =
      %r{
        api\.[^.]*\.ghe\.com/repos/#{NWO_PATH_PATTERN}|
        (?<![a-zA-Z0-9\-.])[a-zA-Z0-9-]+\.ghe\.com/#{NWO_PATH_PATTERN}|
        #{PROXIMA_INTERNAL_HOSTNAME_PATTERN}/repos/#{NWO_PATH_PATTERN}
      }x

    REPO_COLLABORATOR_PERMISSION_PATTERN =
      %r{
        #{PROXIMA_INTERNAL_HOSTNAME_PATTERN}/repositories/\d+/collaborators/(?<login>[\w.-]+)/permission
      }x

    TENANT_HOSTNAME_PATTERN = /(?:api\.)?([a-zA-Z0-9-]+)\.ghe\.com/

    REF_NAME_PATTERN = %r{/git/(?:ref|refs|matching-refs)/([^:\s$]*)}

    def self.call(message)
      message = scrub_nwo_cloud(message)
      message = scrub_nwo_proxima(message)
      message = scrub_login_proxima(message)
      message = scrub_tenant(message)
      scrub_ref(message)
    end

    def self.scrub_nwo_cloud(message)
      return message unless (matches = message.to_enum(:scan, REPO_NWO_PATTERN_CLOUD).map { Regexp.last_match })

      matches.each do |nwo|
        message = message.gsub(nwo[:name], "[FILTERED_REPO]")
      end

      message
    end

    def self.scrub_nwo_proxima(message)
      return message unless (matches = message.to_enum(:scan, REPO_NWO_PATTERN_PROXIMA).map { Regexp.last_match })

      matches.each do |nwo|
        # Be more generic in identifying name and owner in case they are the same
        message = message.gsub(nwo[:owner], "[FILTERED_NWO]")
        message = message.gsub(nwo[:name], "[FILTERED_NWO]")
      end

      message
    end

    def self.scrub_login_proxima(message)
      return message unless (matches = message.scan(REPO_COLLABORATOR_PERMISSION_PATTERN))

      matches.flatten.compact.each do |login|
        message = message.gsub(login, "[FILTERED_LOGIN]")
      end

      message
    end

    def self.scrub_tenant(message)
      return message unless (matches = message.scan(TENANT_HOSTNAME_PATTERN))

      matches.flatten.compact.each do |tenant|
        message = message.gsub(tenant, "[FILTERED_TENANT]")
      end

      message
    end

    def self.scrub_ref(message)
      return message unless (matches = message.scan(REF_NAME_PATTERN))

      matches.flatten.compact.each do |ref|
        message = message.gsub(ref, "[FILTERED_REF]")
      end

      message
    end
  end
end
