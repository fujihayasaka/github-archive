# typed: false
# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  self.delivery_job = ApplicationDeliveryJob

  helper :bundle
  helper :mailer_bundle

  def default_url_options
    {
      host: GitHub.host_name_with_tenant,
      protocol: GitHub.ssl ? "https" : "http"
    }
  end

  # Most GitHub emails have the noreply email as the from address.
  default from: proc { github_noreply }

  # This header tell the SMTP server where to send failure bounces.  Since we
  # don't really care about them at support, we route them to the noreply email.
  # Other measures are taken on our SMTP servers to track these bouncing emails.
  # Override this on a case-by-case basis if you like, but you probably don't
  # want to.
  default return_path: proc { GitHub.urls.noreply_address }

  # This header tells email servers "Hey, we don't want to hear about your
  # vacation plans buddy, we don't care."  For most major mail servers it will
  # prevent support from receiving "Out of Office" autoresponders.
  # Again, override if you so desire...
  default "X-Auto-Response-Suppress" => "All"

  DEVTOOLS_TEST_USER_LOGIN = "devtools-email"

  # Allow for email-specific layouts directory in app/views/mailers/layouts
  append_view_path Rails.root.join("app", "views", "mailers")

  before_action :ensure_smtp_enabled
  after_action ApplicationMailer::SetCustomHeaders
  DELIVERY_STAT_NAME = "mailer.delivery"
  after_action do
    mailer_type = self.class.name.underscore.chomp("_mailer")
    GitHub.dogstats.increment(DELIVERY_STAT_NAME, tags: ["mailer:#{mailer_type}", "action:#{action_name}"])
  end

  module Helpers
    extend self

    # A user's name and email address in mail header format. Use this to set From,
    # To, CC, and Reply-To headers.
    #
    # user - A user or organization.
    # email - (Optional) Email address in String form. Will default to the
    #   user's email if none is passed.
    # allow_private - (Optional) Whether or not private email addresses will be
    #   returned. Defaults to true, but should be set to false if the email
    #   could be shown to someone other than the passed user (like for a
    #   From or Reply-To header).
    #
    # Returns the email string with the user's full name if available.
    def user_email(user, email = nil, allow_private: true)
      # Has to be an EMU user object with profile email set
      is_enterprise_managed = !GitHub.single_business_environment? && user.is_a?(User) && user.is_enterprise_managed? && user.profile_email

      if user.is_a?(User)
        email ||= user.email
        if email && !email.include?("+")
          email
        elsif is_enterprise_managed
          email = user.profile_email
        end
      else
        if is_enterprise_managed
          email = user.profile_email
        else
          email ||= user.email
        end
      end

      if !is_enterprise_managed && email && !allow_private
        # Check if the email exists in the system and is set to private.
        email_record = UserEmail.find_by_email(email)
        email = nil if email_record && email_record.private?
      end

      return if email.blank?

      "#{quote_user_name(user)} #{quote_email_address(email)}"
    end

    # Public: An organization's admins' email addresses.
    # Excluding suspended admins and custom excluded. Use this to set
    # From, To, CC, and Reply-To headers.
    #
    # org - An organization to get admins from.
    # except - a list of admins we don't want to include.
    #
    # Returns an Array of String email addresses with
    # the admins' full names (if available).
    def admin_emails(account, except: [])
      emails_for_admins(account, account.admins.to_a - except)
    end

    # Public: An account's billing contact email addresses.
    #
    # account      - A User, Organization, or Business to get billing emails for.
    # include_name - (Optional) Whether or not to include a user's name in mail header format
    #
    # Returns an Array of String email addresses with
    # the billing users' full names (if available).
    def billing_emails(account, include_name: true)
      emails = []
      account.billing_users.each do |billing_user|
        if include_name
          emails << user_email(billing_user, billing_user.billing_email)
        else
          emails << billing_user.billing_email
        end
      end

      emails << account.billing_email if account.is_a?(Business)

      if account.is_a?(Business) || account.organization?
        emails.concat(account.billing_external_emails.pluck(:email))
      end

      # Remove nil entries, as 'user_email' may return nil.
      # Also removes any duplicate emails
      emails.compact.uniq
    end

    # Get the quoted
    def quote_user_name(user)
      real_name = scrub_real_name(user.try(:profile_name).to_s)
      real_name = user.display_login if real_name.blank?
      %{"#{real_name}"}
    end

    # An email address for a notification list in mail header format.
    #
    # Returns the email string with the entity name and owner's name.
    def notifications_list_email(list, email)
      email = quote_email_address(email)
      %{"#{list.name_with_display_owner}" #{email}}
    end

    # Ensure that the profile name doesn't have any characters that
    # will totally throw off the Mailer.
    def safe_name?(name)
      (name =~ /[\/\\\*~\^\`\"\']/).nil?
    end

    # Remove newlines from a real name string; if the real name
    # has too many weird characters, we don't even try. Email
    # them with their username.
    def scrub_real_name(name)
      return unless name && safe_name?(name)
      scrubbed = name.dup
      scrubbed.gsub!(/[\r\n]/, "")
      scrubbed.gsub!(/\s+/, " ")
      scrubbed
    end

    # Wrap an email address in pointy brackets but only if it isn't already.
    def quote_email_address(email)
      email = email.strip
      email = "<#{email}>" if email[0] != "<"
      email
    end

    # Public: Get the emails that are appropriate for the
    # admin of the account.
    # Emails use Bcc for the receipient(s). For organizations, this prevents
    # disclosure of private email addresses to other organization members.
    # If it's a User we get the primary email. If we've
    # got an org we grab all the admins' preferred email addresses for the org.
    #
    #   account - the User or Organization we're trying to email
    #   except -  optional array of users that we don't want to e-mail (e.g.,
    #             because they opted out of a specific notification)
    #
    # Returns a Hash with `:bcc` fields that each contain a String or
    # Array of Strings suitable to be passed into `Bcc` recipients.
    def user_or_admin_recipients(account, except: [])
      { to: [], bcc: admin_emails(account, except: except) }
    end

    def build_admin_recipients_list(account, admins)
      { to: [], bcc: emails_for_admins(account, admins) }
    end

    # Public: Get the billing contact emails that are appropriate for the
    # account.
    # Emails use Bcc for the receipient(s). For organizations, this prevents
    # disclosure of private email addresses to other organization members.
    # If it's a User we get the primary email. If we've got an org we
    # grab all the billing contacts' preferred email addresses for the org.
    #
    #   account - The User, Organization, or Business we're trying to email
    #   include_name - (Optional) Whether or not to include a user's name in mail header format
    #
    # Returns a Hash with `:bcc` fields that each contain a String or
    # Array of Strings suitable to be passed into `Bcc` recipients.
    def user_or_billing_recipients(account, include_name: true)
      emails = billing_emails(account, include_name:)

      if emails.many?
        { to: [], bcc: emails }
      else
        { to: emails, bcc: [] }
      end
    end

    # Public: Get the combined admin and billing contact emails that are appropriate for the account.
    # Emails use Bcc for the recipients when there are multiple addresses. For organizations, this prevents
    # disclosure of private email addresses to other organization members.
    # If it's a User we get the primary email. If we've got an org we grab all the admins'
    # and billing contacts' preferred email addresses for the org.
    #
    #   account - the User, Organization, or Business we're trying to email
    #
    # Returns a Hash with `:to` and `:bcc` fields that each contain a String or
    # Array of Strings suitable to be passed as mail recipients.
    def admin_and_billing_recipients(account)
      emails = admin_emails(account) | billing_emails(account)

      if emails.many?
        { to: [], bcc: emails }
      else
        { to: emails, bcc: [] }
      end
    end

    def github
      %{"GitHub" <#{GitHub.support_email}>}
    end

    def redalert
      %{"GitHub" <redalert@#{GitHub.host_name}>}
    end

    def github_shop
      %{"GitHub Shop" <shop@#{GitHub.host_name}>}
    end

    def github_marketplace
      %{"GitHub Marketplace" <#{GitHub.marketplace_email}>}
    end

    def github_trade_appeals
      %{"GitHub Trade Appeals" <#{GitHub.trade_appeals_email}>}
    end

    def github_trade_sap_bis
      %{"GitHub Trade SAP BIS" <#{GitHub.trade_sap_bis_email}>}
    end

    def microsoft_trade_help
      %{"Microsoft Trade Help" <#{GitHub.microsoft_trade_help_email}>}
    end

    def github_opensource
      %{"GitHub Open Source" <#{GitHub.opensource_email}>}
    end

    def github_guides
      %{"GitHub" <#{GitHub.guides_email}>}
    end

    def github_partnerships
      %{"GitHub" <#{GitHub.partnerships_email}>}
    end

    def github_noreply(from = nil)
      if from
        user_email(from, GitHub.urls.noreply_address)
      else
        %{"GitHub" <#{GitHub.urls.noreply_address}>}
      end
    end

    def multi_tenant_noreply(from = nil)
      if from
        user_email(from, GitHub.urls.noreply_address)
      else
        if GitHub.multi_tenant_enterprise? && GitHub::CurrentTenant.get&.name
          %{"GitHub Enterprise Cloud for #{GitHub::CurrentTenant.get.name}" <#{GitHub.urls.noreply_address}>}
        else
          %{"GitHub" <#{GitHub.urls.noreply_address}>}
        end
      end
    end

    def bcc_log
      GitHub.enterprise? ? [] : ["logs@github.com"]
    end

    # TODO remove this SOOON
    def notification_signature(url)
      "View it on #{GitHub.flavor}:\n#{url}"
    end

    # This method returns a mail object as handled by Premailer.
    #
    # It is invoked as you normally would with the `mail` method in a mailer.
    #
    # Usage:
    #
    # premail(
    #   :to => "user@example.com",
    #   :from => "support@github.com"
    # )
    #
    def premail(*args)
      mail = self.mail(*args)
      convert_to_premail(mail)
    end

    def convert_to_premail(mail, premailer_options: {})
      options = {
        with_html_string: true,
        drop_unmergeable_css_rules: true,
        preserve_style_attribute: true,
        output_encoding: "US-ASCII",
        input_encoding: "UTF-8",
        adapter: :nokogiri,
      }.merge(premailer_options)

      premailer = Premailer.new(mail.html_part.decoded, options)

      # swap the html body for the premailer-processed html
      mail.html_part.body = premailer.to_inline_css
    end

    # This method provides a path to image assets that can
    # be utilized in a view.
    #
    # <img src="<%= image_base_url %>/explore/octocat.v2.png">
    #
    def image_base_url
      "#{GitHub.mailer_asset_host_url}/images/email"
    end

    # This method provides a path to image assets that can
    # be utilized in a view.
    #
    # <img src="<%= image_url("/explore/octocat.v2.png") %>">
    #
    def image_url(path)
      mailer_static_asset_path("/images/email#{path}")
    end

    private

    # Private: Links to be rendered in the footer of the email
    # when using layouts/primer_layout.
    #
    # Returns Array of Hash.
    def footer_links
      links = []

      links << { url: settings_email_preferences_url, text: "Manage your #{GitHub.flavor} email preferences" }
      unless GitHub.enterprise?
        links << { url: "#{GitHub.help_url}/articles/github-terms-of-service/", text: "Terms" }
        links << { url: "#{GitHub.help_url}/articles/github-privacy-policy/", text: "Privacy" }
      end
      links << { url: login_url, text: "Sign in to #{GitHub.flavor}" }

      links
    end

    # Send an email to a broad set of email addresses while preserving privacy.
    # Emails the primary email address and BCCs the remaining
    # account_related_emails:
    #   * the backup address (if set) OR
    #   * all notifiable_emails:
    #     * All verified email addresses OR
    #     * All emails if no there are no verified emails
    private def mail_to_primary_bcc_remaining_account_related_emails(subject:, template_name:, categories: nil)
      primary_email = GitHub.multi_tenant_enterprise? ? @user.outbound_email : @user.email
      bcc = @user.account_related_emails.map(&:to_s) - [primary_email]

      mail_opts = {
        to: user_email(@user, primary_email),
        bcc: bcc.map { |email| user_email(@user, email) },
        subject: subject,
        template_name: template_name,
      }

      if categories
        mail_opts[:categories] = categories
      end

      mail(mail_opts)
    end

    # Send an primer ready email to a broad set of email addresses while
    # preserving privacy.
    #
    # Emails the primary email address and BCCs the remaining
    # account_related_emails:
    #   * the backup address (if set) OR
    #   * all notifiable_emails:
    #     * All verified email addresses OR
    #     * All emails if no there are no verified emails
    private def premail_to_primary_bcc_remaining_account_related_emails(subject:, template_name:, categories: nil)
      mail = mail_to_primary_bcc_remaining_account_related_emails(subject: subject, template_name: template_name, categories: categories)
      convert_to_premail(mail)
    end

    # Takes a list of admin users and builds and email address list from
    # Excluding suspended admins. Use this to set
    # From, To, CC, and Reply-To headers.
    #
    # admins - a list of admin users
    #
    # Returns an Array of String email addresses with
    # the admins' full names (if available).
    def emails_for_admins(account, admins)
      admin_mails = admins.map do |admin|
        next if admin.suspended?
        user_email(admin, GitHub.newsies.email(admin, account).value)
      end
      # Remove nil entries, as both 'next' and 'user_email' may return nil.
      admin_mails.compact
    end
  end

  include StaticAssetHelper
  include Helpers

  helper_method :mailer_static_asset_path, :image_url

  private

  def ensure_smtp_enabled
    abort! if ActionMailer::Base.delivery_method == :smtp && !GitHub.smtp_enabled?
  end

  def abort!
    # Setting response_body to a non-nil value terminates the callback.
    # From https://guides.rubyonrails.org/action_mailer_basics.html#action-mailer-callbacks:
    # "Mailer Filters abort further processing if body is set to a non-nil value."
    #
    # See also:
    # https://github.com/rails/rails/blob/d137b10f946ff78fac8fe203d5aeaf2bb4c3a1d9/actionpack/lib/abstract_controller/callbacks.rb#L34
    # https://github.com/rails/rails/blob/d137b10f946ff78fac8fe203d5aeaf2bb4c3a1d9/actionpack/lib/abstract_controller/base.rb#L186-L191
    self.response_body = :abort
  end
end
