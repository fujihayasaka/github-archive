# typed: true
# frozen_string_literal: true

require "github/config/mysql"
require "github-ds"

module GitHub
  module Enterprise
    autoload :License,     "github/enterprise/license"
    autoload :Middleware,  "github/enterprise/middleware"
    autoload :CronEntry,   "github/enterprise/cron_entry"
    autoload :Certificate, "github/enterprise/certificate"

    DEFAULT_MAINTENANCE_MODE_MESSAGE = "Your GitHub Enterprise administrators are performing scheduled maintenance.".freeze
    MAINTENANCE_MODE_MESSAGE_FILE = "/data/user/common/maintenance_mode_message.txt".freeze

    # Adds `enterprise?` where included, both as instance and class methods.
    module Behavior
      def enterprise?
        GitHub.enterprise?
      end

      def self.included(target)
        target.extend ClassMethods
      end

      module ClassMethods
        def enterprise?
          GitHub.enterprise?
        end
      end
    end

    # Determine whether a backup-utils backup is in progress. When a backup is
    # in progress no git GC or repack operations may be performed since that can
    # result in backups being captured in an inconsistent state. For more
    # information see:
    # <https://github.com/github/backup-utils/blob/master/share/github-backup-utils/ghe-backup-repositories-rsync>
    def self.backup_in_progress?
      GitHub.enterprise? && File.exist?("#{GitHub.repository_root}/.sync_in_progress")
    end

    # Path to file that signals that a backup-utils backup is in progress. This
    # file is created when ghe-backup starts a backup and is unlinked when the
    # operation is completed.
    def self.backup_in_progress_file
      "#{GitHub.repository_root}/.sync_in_progress"
    end

    # Public - Check the Enterprise maintenance key to see if maintenance is scheduled
    #
    # Returns the formatted time when maintenance will begin, or nil if a maintenance
    # time has not been set.
    def self.maintenance_scheduled
      if maintenance_time = GitHub.kv.get("enterprise:maintenance").value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        begin
          time = Time.iso8601(maintenance_time)
        rescue ArgumentError
          # Parsing the time using #iso8601 failed
          return nil
        end

        time.in_time_zone.strftime("%A, %B %-d at %k:%M %z")
      end
    end

    # Path to file that contains the custom maintenance mode message. This
    # file is created at appliance start and mounted to github-env container
    def self.maintenance_mode_message_file
      if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test?
        "/tmp/maintenance_mode_message.txt"
      else
        MAINTENANCE_MODE_MESSAGE_FILE
      end
    end

    # Public - Check the maintenance mode message text file in enterprise to render
    # maintenance page and notification
    #
    # Returns the text from file if file is found and text is not empty,
    # or DEFAULT_MAINTENANCE_MODE_MESSAGE
    def self.maintenance_mode_message
      begin
        msg = File.read(maintenance_mode_message_file, encoding: "UTF-8")
        maintenance_mode_message = msg.strip.presence || DEFAULT_MAINTENANCE_MODE_MESSAGE
      rescue Errno::ENOENT
        maintenance_mode_message = DEFAULT_MAINTENANCE_MODE_MESSAGE
      end
      maintenance_mode_message
    end

    # Public - Check if there's an announcement
    #
    # Returns the announcement text
    def self.announcement
      announcement = GitHub::EnterpriseAnnouncement.get_announcement
      if announcement.text.present?
        result = GitHub::Goomba::MarkdownPipeline.call(announcement.text, {})
        output = result[:output]
        announcement.text_html = output.html_safe if result[:html_safe] # rubocop:disable Rails/OutputSafety
      end
      announcement
    end

    # Instantiate and memoize the License object for this Enterprise install
    # using the settings defined in GitHub::Config.
    #
    # Returns a License.
    def self.license(sync_global_business: true)
      if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test?
        @license ||= LicenseMock.new
      else
        @license ||= License.new(sync_global_business: sync_global_business)
      end
    end

    if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test?
      require "active_support/core_ext/integer/time"

      class LicenseMock < License
        attr_writer :company, :expire_at, :seats, :perpetual, :unlimited, :evaluation, :github_connect_support, :advanced_security_enabled, :advanced_security_seats, :metered
        attr_writer :seats_used

        def initialize(
          expire_at: 1.year.from_now.to_datetime,
          seats: 0,
          perpetual: false,
          unlimited: true,
          evaluation: false,
          github_connect_support: true,
          custom_terms: nil,
          advanced_security_enabled: true,
          advanced_security_seats: nil,
          metered: false,
          company: "ACME, Inc")
          @company, @expire_at, @seats, @perpetual, @unlimited, @evaluation, @github_connect_support, @custom_terms, @advanced_security_enabled, @advanced_security_seats, @metered =
            company, expire_at, seats.to_i, perpetual, unlimited, evaluation, github_connect_support, custom_terms, advanced_security_enabled, advanced_security_seats, metered
        end

        def reload!; true end

        def seats_used
          return @seats_used if @seats_used
          super
        end

        def github_connect_support
          return @github_connect_support if @github_connect_support
          super
        end
        alias github_connect_support? github_connect_support

        def custom_terms
          @custom_terms
        end

        def custom_terms?
          return !!@custom_terms if @custom_terms
          super
        end

        def license_data
          "ohana means family"
        end
      end

      def metered
        !!@metered
      end
      alias metered? metered

      def self.license_reset!(options = {})
        @license = LicenseMock.new(**options)
      end

      license_reset!
    end

    # Instantiate and memoize the GitHub::Enterprise::Certificate object for
    # this Enterprise installation.
    #
    # Returns a GitHub::Enterprise::Certificate if Enterprise, otherwise nil.
    def self.certificate
      return nil if !GitHub.enterprise? || !GitHub.ssl?
      @certificate ||= Certificate.new(
        OpenSSL::X509::Certificate.new(GitHub.ssl_certificate),
      )
    end

    def self.certificate_reset!(x509_certificate)
      @certificate = Certificate.new(x509_certificate)
    end

    def self.ensure_business!
      GitHub.load_activerecord

      business_count = ApplicationRecord::Domain::Users.connection.select_value(<<-SQL)
        SELECT count(id) FROM businesses
      SQL

      unless business_count == 0
        puts "Existing enterprise account found. Skipping creating a global enterprise account."
        return
      end

      license = GitHub::Enterprise.license(sync_global_business: false)
      slug = license.company.parameterize.presence || GitHub.default_business_base_slug

      ApplicationRecord::Domain::Users.connection.insert(Arel.sql(<<-SQL, name: license.company, slug: slug, seats: license.seats))
        INSERT IGNORE INTO businesses (id, name, slug, created_at, updated_at, seats)
        VALUES
          (1, :name, :slug, NOW(), NOW(), :seats)
      SQL
    end

    def self.ensure_customer!
      GitHub.load_activerecord

      business_count = ApplicationRecord::Domain::Users.connection.select_value(<<-SQL)
        SELECT count(id) FROM businesses
      SQL

      unless business_count == 1
        puts "No global enterprise account found. Cannot create a global customer."
        return
      end

      customer_count = ApplicationRecord::Domain::Users.connection.select_value(<<-SQL)
        SELECT count(id) FROM customers
      SQL

      unless customer_count == 0
        puts "Existing customer record found. Skipping creating a global customer."
        return
      end

      ApplicationRecord::Domain::Users.connection.insert(Arel.sql(<<-SQL, name: license.company, uuid: SecureRandom.uuid))
        INSERT IGNORE INTO customers (id, name, created_at, updated_at, external_uuid)
        VALUES
          (1, :name, NOW(), NOW(), :uuid)
      SQL

      ApplicationRecord::Domain::Users.connection.update(<<-SQL)
        UPDATE businesses SET customer_id=1 where id=1
      SQL
    end

    # This method is used to disable SCIM when SAML has been turned off in enterprise-manage
    def self.disable_scim!
      GitHub.load_activerecord

      return unless GitHub.single_business_environment?
      return unless GitHub.global_business

      provider = GitHub.global_business.external_provider
      return unless provider

      # If SAML is enabled, we need to check if the SAML configurations have changed. If they have changed, we'll
      # destroy the provider and disable SCIM.
      # In GHEC, any SSO updates will result in a new provider being created. This matches that behavior, with the
      # added step of requiring that the customer
      if GitHub.auth.saml?
        # sso url or issuer changes need to result in the destruction of the provider
        # IdP certificate or digest / signature changes do not require the provider to be destroyed
        # See app/views/businesses/settings/security/_saml_form.html.erb for the fields we allow customers to edit
        # and not edit in GHEC without disabling the provider
        saml_sso_url_changed = GitHub.saml_sso_url != provider.sso_url
        issuer_changed = GitHub.saml_issuer != provider.issuer

        return unless saml_sso_url_changed || issuer_changed
      end

      Business.transaction do
        first_admin = GitHub.global_business.owners.first
        GitHub.global_business.disable_open_scim(actor: first_admin) if first_admin

        provider = provider.destroy
        unless provider
          puts "Failed to disable SCIM: Unable to destroy external provider"
          raise ActiveRecord::Rollback
        end
      end
    rescue Configurable::OpenSCIM::OpenSCIMError
      puts "Failed to disable SCIM: Unable to disable open scim"
    end
  end
end
