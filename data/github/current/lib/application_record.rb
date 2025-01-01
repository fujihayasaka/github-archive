# typed: true
# frozen_string_literal: true

module ApplicationRecord
  autoload :Authnd, "application_record/authnd"
  autoload :Ballast, "application_record/ballast"
  autoload :Base, "application_record/base"
  autoload :Billing, "application_record/billing"
  autoload :Collab, "application_record/collab"
  autoload :Commits, "application_record/commits"
  autoload :Configurations, "application_record/configurations"
  autoload :Copilot, "application_record/copilot"
  autoload :Domain, "application_record/domain"
  autoload :Gitbackups, "application_record/gitbackups"
  autoload :Iam, "application_record/iam"
  autoload :IamAbilities, "application_record/iam_abilities"
  autoload :Lodge, "application_record/lodge"
  autoload :Memex, "application_record/memex"
  autoload :Migrations, "application_record/migrations"
  autoload :Mysql1, "application_record/mysql1"
  autoload :Mysql2, "application_record/mysql2"
  autoload :Mysql5, "application_record/mysql5"
  autoload :NotificationsDeliveries, "application_record/notifications_deliveries"
  autoload :NotificationsEntries, "application_record/notifications_entries"
  autoload :NotificationsSummaries, "application_record/notifications_summaries"
  autoload :Notify, "application_record/notify"
  autoload :Permissions, "application_record/permissions"
  autoload :Repositories, "application_record/repositories"
  autoload :RepositoriesActionsChecks, "application_record/repositories_actions_checks"
  autoload :IssuesPullRequests, "application_record/issues_pull_requests"
  autoload :RepositoriesPushes, "application_record/repositories_pushes"
  autoload :SecurityOverviewAnalytics, "application_record/security_overview_analytics"
  autoload :Sharding, "application_record/base/sharding"
  autoload :Spokes, "application_record/spokes"
  autoload :Stratocaster, "application_record/stratocaster"
  autoload :TokenScanningService, "application_record/token_scanning_service"
  autoload :UTCRecord, "application_record/base/utc_record"
  autoload :UTCTimeType, "application_record/base/utc_time_type"
  autoload :VT, "application_record/vt"
  autoload :SignupFlow, "application_record/signup_flow"

  def self.connection_info
    return @connection_info if defined?(@connection_info)
    connection_handler = ApplicationRecord::Base.connection_handler # rubocop:disable GitHub/DontCallApplicationRecordBaseMethods

    @connection_info = connection_handler.connection_pool_list(:all).each_with_object({}) do |connection_pool, hash|
      pool_config = connection_pool.pool_config

      # The name of the connected pool
      # => in 6.1 ActiveRecord::Base is now always ActiveRecord::Base.
      pool_name = pool_config.connection_name

      # configuration hash
      config = pool_config.db_config.configuration_hash

      # Turns "ActiveRecord::Base" into "mysql1", "ApplicationRecord::Ballast" into "ballast"
      name = pool_name == "ActiveRecord::Base" ? "mysql1" : pool_name.demodulize.downcase

      hash[name] = "#{config[:username]}@#{config[:host]}#{config[:socket]}/#{config[:database]}"
    end
  end

  def self.clusters
    return @clusters if defined?(@clusters)

    @clusters = if ActiveRecord::Base.single_database_cluster?
      [ApplicationRecord::Mysql1]
    else
      ApplicationRecord::Base.subclasses # rubocop:disable GitHub/DontCallApplicationRecordBaseMethods
    end
  end
end
