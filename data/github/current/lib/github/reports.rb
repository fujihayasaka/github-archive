# typed: true
# frozen_string_literal: true

module GitHub
  module Reports
    require "github/reports/cache"
    require "github/reports/active_users"
    require "github/reports/all_organizations"
    require "github/reports/all_repositories"
    require "github/reports/all_users"
    require "github/reports/dormant_users"
    require "github/reports/enterprise_users"
    require "github/reports/suspended_users"

    REPORTS = {
      active_users: ActiveUsers,
      all_organizations: AllOrganizations,
      all_repositories: AllRepositories,
      all_users: AllUsers,
      dormant_users: DormantUsers,
      enterprise_users: EnterpriseUsers,
      suspended_users: SuspendedUsers,
    }

    def self.update(name)
      report = cached(name)

      if report.cached?
        return
      end

      GitHub.dogstats.time("stafftools_report", tags: ["type:#{name}"]) do
        report.update!
      end
    end

    def self.cached(name)
      klass = class_for(name)
      cache = Cache.new(name, klass.new)
      cache.clear if GitHub.cache.skip

      cache
    end

    def self.cached_data_or_enqueue_job(name)
      report = cached(name)

      if report.cached?
        report.data
      else
        report.update
        nil
      end
    end

    def self.class_for(report)
      REPORTS[report.to_sym]
    end

    # Generates a report in CSV format containing all organizations.
    #
    # Returns String of CSV data.
    def self.all_organizations
      cached_data_or_enqueue_job(:all_organizations)
    end

    # Generates a report in CSV format containing all repositories.
    #
    # Returns String of CSV data.
    def self.all_repositories
      cached_data_or_enqueue_job(:all_repositories)
    end

    # Generates a report in CSV format containing all the users who aren't
    # dormant and haven't been suspended.
    #
    # Returns String of CSV data.
    def self.active_users
      cached_data_or_enqueue_job(:active_users)
    end

    # Generates a report in CSV format containing all organization users.
    #
    # Returns String of CSV data.
    def self.all_users
      cached_data_or_enqueue_job(:all_users)
    end

    # Generates a report in CSV format containing all dormant users who aren't
    # already suspended and aren't site admins.
    #
    # Returns String of CSV data.
    def self.dormant_users
      cached_data_or_enqueue_job(:dormant_users)
    end

    # Generates a report in CSV format containing all enterprise users.
    #
    # Returns String of CSV data.
    def self.enterprise_users
      cached_data_or_enqueue_job(:enterprise_users)
    end

    # Generates a report in CSV format containing all suspended users.
    #
    # Returns String of CSV data.
    def self.suspended_users
      cached_data_or_enqueue_job(:suspended_users)
    end

    def self.developers
      cached_data_or_enqueue_job(:developers)
    end
  end
end
