# typed: true
# frozen_string_literal: true

module Newsies
  # Describes the settings a User can configure for all notifications.
  # Settings should be stored and retrieved from a Horcrux store.  See
  # Newsies::SettingsStore.
  class Settings
    extend T::Sig

    attr_reader(
      :id,
      :participating_settings,
      :subscribed_settings,
      :org_deploy_key_settings,
      :emails,
      :auto_subscribe_repositories,
      :auto_subscribe_teams,
      :notify_own_via_email,
      :notify_comment_email,
      :notify_pull_request_review_email,
      :notify_pull_request_push_email,
      :vulnerability_cli,
      :vulnerability_web,
      :vulnerability_email,
      :continuous_integration_web,
      :continuous_integration_email,
      :continuous_integration_failures_only,
    )

    attr_accessor :user, :direct_mention_mobile_push

    alias auto_subscribe_repositories? auto_subscribe_repositories
    alias auto_subscribe_teams? auto_subscribe_teams
    alias notify_own_via_email? notify_own_via_email
    alias notify_comment_email? notify_comment_email
    alias notify_pull_request_review_email? notify_pull_request_review_email
    alias notify_pull_request_push_email? notify_pull_request_push_email
    alias vulnerability_cli? vulnerability_cli
    alias vulnerability_web? vulnerability_web
    alias vulnerability_email? vulnerability_email
    alias continuous_integration_web? continuous_integration_web
    alias continuous_integration_email? continuous_integration_email
    alias continuous_integration_failures_only? continuous_integration_failures_only
    alias direct_mention_mobile_push? direct_mention_mobile_push

    def initialize(id = nil)
      identify(id) if id
      @participating_settings = []
      @subscribed_settings = []
      @org_deploy_key_settings = [Newsies::HANDLER_EMAIL]
      @emails = {}
      @auto_subscribe_repositories = false
      @auto_subscribe_teams = true
      @notify_own_via_email = false
      @notify_comment_email = true
      @notify_pull_request_review_email = true
      @notify_pull_request_push_email = true
      @vulnerability_cli = true
      @vulnerability_web = true
      @vulnerability_email = true
      @continuous_integration_web = false
      @continuous_integration_email = true
      @continuous_integration_failures_only = true
      @direct_mention_mobile_push = false
    end

    # Public: returns whether the user receives web notifications for activity
    # in the issues they are participating
    sig { returns T::Boolean }
    def participating_web?
      participating_settings.include? Newsies::HANDLER_WEB
    end

    # Public: set whether the user receives web notifications for activity on
    # which they are participating.
    #
    # value - A truthy object determining whether the user receives
    #         notifications for activity on which they are participating.
    #
    # Returns nothing.
    def participating_web=(value)
      if value
        participating_settings << Newsies::HANDLER_WEB
        participating_settings.uniq!
      else
        participating_settings.delete(Newsies::HANDLER_WEB)
      end
    end

    # Public: returns whether the user receives email notifications for activity
    # in the issues they are participating
    sig { returns T::Boolean }
    def participating_email?
      participating_settings.include? Newsies::HANDLER_EMAIL
    end

    # Public: returns whether the user receives web notifications for activity
    # in the issues they are subscribed to
    sig { returns T::Boolean }
    def subscribed_web?
      subscribed_settings.include? Newsies::HANDLER_WEB
    end

    # Public: set whether the user receives web notifications for activity to
    # which they are subscribed.
    #
    # value - A truthy object determining whether the user receives
    #         notifications for activity to which they are subscribed.
    #
    # Returns nothing.
    def subscribed_web=(value)
      if value
        subscribed_settings << Newsies::HANDLER_WEB
        subscribed_settings.uniq!
      else
        subscribed_settings.delete(Newsies::HANDLER_WEB)
      end
    end

    # Public: returns whether the user receives email notifications for deploy
    # keys added to repos in orgs they admin
    sig { returns T::Boolean }
    def org_deploy_key_email?
      org_deploy_key_settings.include? Newsies::HANDLER_EMAIL
    end

    # Public: set whether the user receives email notifications for deploy
    # keys added to repos in orgs they admin
    #
    # value - A truthy object determining whether the user receives
    #         notifications for activity to which they are subscribed.
    #
    # Returns nothing.
    def org_deploy_key_email=(value)
      if value
        org_deploy_key_settings << Newsies::HANDLER_EMAIL
        org_deploy_key_settings.uniq!
      else
        org_deploy_key_settings.delete(Newsies::HANDLER_EMAIL)
      end
    end

    # Public: returns whether the user receives email notifications for activity
    # in the issues they are subscribed to
    sig { returns T::Boolean }
    def subscribed_email?
      subscribed_settings.include? Newsies::HANDLER_EMAIL
    end

    # Public: Either gets or sets the email.  Users have a global email for
    # all notifications, or a specific one for Organizations. If an address is
    # not set for the organization, the global email will be used. If a
    # global address is not set, the user's email address will be used.
    #
    #   # get global email
    #   @settings.email :global # UserSettings::Email
    #
    #   # get org email
    #   @settings.email some_org # UserSettings::Email
    #
    #   # set global email
    #   @settings.email :global, 'foo@bar.com'
    #
    #   # set org email
    #   @settings.email some_org, 'foo+org@bar.com'
    #
    # key   - Some object that can be serialized to a valid email key.  Either
    #         a String like Newsies::SETTINGS_EMAILS_GLOBAL or "org-{org_id}", or an Organization.
    # *args - One or more arguments to build a Newsies::Settings::Email.  See #build.
    #         If this is blank, assume we are getting the value.
    #
    # Returns a Newsies::Settings::Email.
    def email(key, *args)
      real_key = case key
      when String then key
      when Symbol then key.to_s
      when Organization then "org-#{key.id}"
      end

      if !Email.key?(real_key)
        raise ArgumentError, "Invalid key of class #{key.class}"
      end

      if args.present?
        if email = T.unsafe(Email).build(*args)
          @emails[real_key] = email
        else
          @emails.delete real_key
        end
      else
        @emails[real_key] || default_email
      end
    end

    # Public: Yields custom routed emails for the user's organizations.
    #
    # filter_restricted_orgs - A Boolean indicating if the result should exclude
    # organizations that the user is not eligible to receive email notifications
    # from due to notification restrictions.
    #
    # Yields an Organization and a Newsies::Settings::Email object.
    # Returns nothing.
    def organization_emails(filter_restricted_orgs: false)
      def_address = default_email
      orgs = filter_restricted_orgs ? email_notification_eligible_organizations : user.affiliated_organizations
      orgs.each do |org|
        email = email(org)
        yield org, email unless email.address == def_address
      end
      nil
    end

    # Sorts custom routed emails for organizations into a Hash.
    #
    # filter_restricted_orgs - A Boolean indicating if the result should exclude
    # organizations that the user is not eligible to receive email notifications
    # from due to notification restrictions.
    #
    # Returns a Hash with String email address keys and Array[Organization] values.
    def organizations_by_email(filter_restricted_orgs: false)
      @organizations_by_email ||= Hash.new do |h, filter_arg|
        h[filter_arg] = begin
          hash = {}
          organization_emails(filter_restricted_orgs: filter_arg) do |org, email|
            hash[email.address] ||= []
            hash[email.address] << org
          end
          hash
        end
      end
      @organizations_by_email[filter_restricted_orgs]
    end

    # Public: get a list of organizations for which this user doesn't currently receive
    # notifications. An organization is included if it has restricted notifications to verified
    # and approved domains only, and the user does not have an email address from one of the
    # org's verified or approved domains.
    sig { returns T::Array[Organization] }
    def restricted_organizations
      return [] if user.nil?

      organizations = user.organizations.includes(:business)
      # pre-load the Configurable entries for all the organizations, so we don't have to
      # load them separately when checking if notifications are restricted
      Configurable.preload_configuration(organizations)

      organizations.select do |organization|
        organization.restrict_notifications_to_verified_domains? &&
          !organization.user_has_email_eligible_domain_notification_email?(user)
      end
    end

    def settings_enabled_for?(handler_key)
      handler = handler_key.to_s

      participating_settings.include?(handler) ||
        subscribed_settings.include?(handler) ||
        vulnerability_settings.include?(handler) ||
        continuous_integration_settings.include?(handler) ||
        org_deploy_key_settings.include?(handler)
    end

    # Public: Clear invalid Newsies::Settings::Email records.
    #
    # verified      - A Set of downcased String email addresses.
    # primary_email - An optional downcased String primary email address.
    #
    # Returns nil or an Array of unverified String email addresses.
    def clear_unverified_emails(verified, primary_email = nil)
      cleared = []
      @emails.each_key do |key|
        email = @emails[key]
        next if verified.include?(email.address.try(:downcase))
        @emails.delete(key)
        cleared << email.address
      end
      @emails[Newsies::SETTINGS_EMAILS_GLOBAL] ||= Email.build(primary_email) if primary_email
      cleared.present? ? cleared : nil
    end

    sig { returns T.nilable(Email) }
    def default_email
      if email = @emails[Newsies::SETTINGS_EMAILS_GLOBAL]
        Email.new(email.address, fallback: true)
      else
        if user.present?
          notification_email = user.default_notification_email
          Email.new(notification_email, fallback: true)
        end
      end
    end

    # Public: #notify_own_via_email attribute writer that ensures the value is always
    # a boolean.
    #
    # value - A truthy object determining whether the user receives notifications
    #         for their own actions.
    #
    # Returns nothing.
    def notify_own_via_email=(value)
      @notify_own_via_email = !!value
    end

    # Public: #notify_comment_email attribute writer that ensures the value is always
    # a boolean.
    #
    # value - A truthy object determining whether the user receives email notifications
    #         for comments
    #
    # Returns nothing.
    def notify_comment_email=(value)
      @notify_comment_email = !!value
    end

    # Public: #notify_pull_request_review_email attribute writer that ensures the value is always
    # a boolean.
    #
    # value - A truthy object determining whether the user receives email notifications
    #         for pull request reviews
    #
    # Returns nothing.
    def notify_pull_request_review_email=(value)
      @notify_pull_request_review_email = !!value
    end

    # Public: #notify_pull_request_push_email attribute writer that ensures the value is always
    # a boolean.
    #
    # value - A truthy object determining whether the user receives email notifications
    #         for pushes to pull requests
    #
    # Returns nothing.
    def notify_pull_request_push_email=(value)
      @notify_pull_request_push_email = !!value
    end

    def vulnerability_cli=(value)
      @vulnerability_cli = !!value
    end

    def vulnerability_web=(value)
      @vulnerability_web = !!value
    end

    def vulnerability_email=(value)
      @vulnerability_email = !!value
    end

    sig { returns T::Array[String] }
    def vulnerability_settings
      vuln_handlers = []
      vuln_handlers.push("cli") if vulnerability_cli?
      vuln_handlers.push("web") if vulnerability_web?
      vuln_handlers.push("email") if vulnerability_email?
      vuln_handlers
    end

    sig { returns T::Boolean }
    def continuous_integration_enabled?
      continuous_integration_settings.any?
    end

    def continuous_integration_web=(value)
      @continuous_integration_web = !!value
    end

    def continuous_integration_email=(value)
      @continuous_integration_email = !!value
    end

    def continuous_integration_failures_only=(value)
      @continuous_integration_failures_only = !!value
    end

    sig { returns T::Boolean }
    def continuous_integration_all_results?
      !continuous_integration_failures_only?
    end

    sig { returns T::Array[String] }
    def continuous_integration_settings
      ci_handlers = []

      ci_handlers << "web" if continuous_integration_web?
      ci_handlers << "email" if continuous_integration_email?

      ci_handlers
    end

    def subscribed_vulnerability_digest?(user)
      subscription = NewsletterSubscription.where("user_id = ? AND name = ?", user.id, "vulnerability").first
      subscription&.active?
    end

    # Public: #auto_subscribe_repositories attribute writer that ensures the value is always
    # a boolean.
    #
    # value - A truthy object determining whether the user auto subscribes to repository lists.
    #
    # Returns nothing.
    def auto_subscribe_repositories=(value)
      @auto_subscribe_repositories = !!value
    end

    # For backwards compatibility
    alias :auto_subscribe= :auto_subscribe_repositories=
    alias :auto_subscribe? :auto_subscribe_repositories?
    alias :auto_subscribe :auto_subscribe_repositories

    # Public: #auto_subscribe_teams attribute writer that ensures the value is always a boolean.
    #
    # value - A truthy object determining whether the user auto subscribes to team lists.
    #
    # Returns nothing.
    def auto_subscribe_teams=(value)
      @auto_subscribe_teams = !!value
    end

    # Public: Tells whether this Settings is identified with a specific
    # user.  You can call #id to get the User's ID.
    #
    # Returns true if this Settings is saved with a User, or false.
    sig { returns T::Boolean }
    def identified?
      !!@id
    end

    # Public Tells whether this Settings is brand new.
    #
    # Returns true if this Settings is new, or false if it is saved with a
    # User.
    sig { returns T::Boolean }
    def new?
      !@id
    end

    # Public: Sets the identify of this Settings.
    #
    # id - An Integer User ID.
    #
    # Returns this Settings.
    sig { params(id: Integer).returns(Newsies::Settings) }
    def identify(id)
      @id = id.to_i
      self
    end

    # Public: The User that the notification settings belong to.
    #
    # Returns a Promise resolving to a User or nil.
    sig { returns Promise[T.nilable(User)] }
    def async_user
      if user
        Promise.resolve(user)
      else
        Promise.resolve(nil)
      end
    end

    def ==(other)
      self.class == other.class &&
        id == other.id &&
        participating_settings == other.participating_settings &&
        subscribed_settings == other.subscribed_settings &&
        auto_subscribe_repositories == other.auto_subscribe_repositories &&
        auto_subscribe_teams == other.auto_subscribe_teams &&
        org_deploy_key_settings == other.org_deploy_key_settings &&
        emails == other.emails
    end
    alias_method :eql?, :==

    # Public: Describes a User email address.
    class Email
      attr_accessor :address, :fallback

      # fallback / fallback? is used to tell the consumer of the class wehther
      # this email is set because it's the deafult email address for the user i.e. a fallback.
      # It's upto the creators of the object to set whether the email address being used is a fallback or not.
      alias :fallback? :fallback

      def initialize(address = nil, fallback: false)
        @address = address.to_s
        @fallback = fallback
      end

      def self.build(address)
        if address.is_a?(self)
          address
        elsif address.blank?
          nil
        else
          new address
        end
      end

      def self.key?(key)
        key.to_s =~ /\A(org-\d+)|(global)\z/
      end

      def ==(other)
        self.address == other.address
      end
      alias_method :eql?, :==
    end

    private

    # Private: The organizations the user is affiliated with where the user is
    # able to receive email notifications.
    #
    # See also Organization#user_can_receive_email_notifications
    sig { returns T::Array[Organization] }
    def email_notification_eligible_organizations
      organizations_with_roles = user.affiliated_organizations_with_roles
      organizations = organizations_with_roles.keys

      return [] unless organizations.any?

      eligible_orgs = []

      email_eligible_domains_by_org = VerifiableDomain.verified_or_approved.where(
        owner_id: organizations.pluck(:id),
        owner_type: "User",
      ).group_by(&:owner_id)

      business_ids = []
      Organization.where(id: organizations.pluck(:id)).includes(:business).each do |org|
        next unless org.business.present?
        business_ids << org.business.id
      end
      email_eligible_domains_by_business = VerifiableDomain.verified_or_approved.where(
        owner_id: business_ids.uniq,
        owner_type: "Business",
      ).group_by(&:owner_id)

      organizations.each do |org|
        # an organization is always eligible to be included unless the user is a
        # direct member of the organization and notification restrictions are enabled.
        roles = organizations_with_roles[org]
        next eligible_orgs << org unless org.restrict_notifications_to_verified_domains? &&
                                         (roles.include?(:admin) || roles.include?(:member))

        configured_email = email(org)&.address
        next unless configured_email.present?

        _, domain = configured_email.split("@")
        email_eligible_domains = (email_eligible_domains_by_org[org.id] || []).map(&:domain)
        if business_id = org.business&.id
          email_eligible_domains += (email_eligible_domains_by_business[business_id] || []).map(&:domain)
        end

        email_eligible_domains.uniq!
        # if the domain of the configured routing email matches a verified or approved
        # domain in the organization, the user is eligible to receive notifications for
        # that organization.
        eligible_orgs << org if email_eligible_domains.include?(domain)
      end

      eligible_orgs
    end
  end
end
