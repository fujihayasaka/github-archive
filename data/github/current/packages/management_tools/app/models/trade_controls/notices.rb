# typed: strict
# frozen_string_literal: true

module TradeControls
  module Notices
    # --- READ THIS BEFORE DOING ANY CHANGE IN THIS FILE ---
    # All the user facing messages in this file need to go through extra approval if they need to be changed.
    # If you need to change any of these, please follow these steps:
    # - Ping `@trade-controls-reviewers`.
    # - Make sure the change(s) are approved by legal and comms teams.
    #
    # If you have any questions please jump into `#pe-trade-compliance` on slack.


    APPEALS_URL = "https://airtable.com/shrGBcceazKIoz6pY"

    APPEALS_URL_GENERIC = T.let("#{GitHub.help_url}/github/site-policy/github-and-trade-controls#how-is-github-ensuring-that-folks-not-living-in-andor-having-professional-links-to-the-sanctioned-countries-and-territories-still-have-access-or-ability-to-appeal", String)

    DUE_TO_LAW = "Due to U.S. trade controls law restrictions,"

    US_SANCTIONED_REGION = "It appears your account may be based in a U.S.-sanctioned region."

    US_SANCTIONED_REGION_NON_ADMIN = "It appears this account may be based in a U.S.-sanctioned region."

    PAID_SERVICES_SUSPENDED = T.let(<<~TEXT.chomp, String)
      This means we have suspended access to private repository services and paid services for your account. \
      For free individual accounts, you still have access to free GitHub public repository services \
      (such as public repositories for open source projects and associated GitHub Pages and Gists).
    TEXT

    FILE_APPEAL = T.let(<<~HTML.chomp, String)
      If you believe your account has been flagged in error, \
      and you are not located in or resident in a sanctioned region, \
      please <a href=#{APPEALS_URL}>file an appeal</a>.
    HTML

    ORG_FILE_APPEAL = T.let(<<~TEXT.chomp, String)
      If you believe your organization’s account has been flagged in error, \
      and is not affiliated with a U.S.-sanctioned jurisdiction, please file \
      an appeal.
    TEXT

    ORG_FILE_APPEAL_GENERIC = T.let(<<~HTML.chomp, String)
      If your account has been flagged in error, \
      and you are not located in or resident in a sanctioned region, \
      please <a href=#{APPEALS_URL_GENERIC}>file an appeal</a>.
    HTML

    ORG_FILE_APPEAL_SDN_RESTRICTION_GENERIC = T.let(<<~HTML.chomp, String)
      If your account has been flagged in error, \
      please <a href=#{APPEALS_URL_GENERIC}>file an appeal</a>.
    HTML

    MORE_INFO = T.let(<<~HTML.chomp, String)
      Please read about <a href=#{GitHub.trade_controls_help_url}>\
      GitHub and Trade Controls</a> for more information.
    HTML

    NON_ADMIN_MORE_INFO = T.let(<<~HTML.chomp, String)
      Please contact the organization admin and read about \
      <a href=#{GitHub.trade_controls_help_url}>\
      GitHub and Trade Controls</a> for more information.
    HTML

    PAID_ORG_SERVICES_BASE = T.let(<<~TEXT.chomp, String)
      For free organizations, you may have access to free GitHub public repository \
      services (such as access to GitHub Pages and public repositories used for open source projects) \
      for personal communications only, and not for commercial purposes.
    TEXT

    PAID_ORG_SERVICES_SUSPENDED = T.let(<<~TEXT.chomp, String)
      #{PAID_ORG_SERVICES_BASE} The restriction also includes \
      suspended access to private repository services and paid services (such as availability of \
      private organizational accounts and GitHub Marketplace services).
    TEXT

    ARCHIVED = T.let(<<~TEXT.chomp, String)
      This repository has been archived with read-only access.
    TEXT

    UNABLE_TO_PROVIDE_ACCESS = "We are unable to provide access to GitHub private repository services."

    # Templates
    GENERIC_RESTRICTION_TEMPLATE = T.let(<<~HTML.chomp, String)
      #{US_SANCTIONED_REGION} As a result, we are unable to \
      provide private repository services and paid services for your account. \
      GitHub has preserved, however, your access to <a href=#{GitHub.trade_controls_services_available_url}>certain free services for public repositories</a>. \

      #{ORG_FILE_APPEAL_GENERIC} #{MORE_INFO}
    HTML

    ACCOUNT_SDN_SPAMMY_TEMPLATE = T.let(<<~HTML.chomp, String)
      Your account has been flagged. Because of that, your account is ineligible for transactions with GitHub. \
      If you believe this is a mistake, <a href=#{GitHub.contact_support_url}/reinstatement target="_blank">contact support</a> to have your \
      account status reviewed.
    HTML

    RESTRICTED_FREE_ORG_ALLOWED_TEMPLATE = T.let(<<~HTML.chomp, String)
      Thanks for your patience while we reviewed this account. It has been cleared \
      and you're now free to make purchases or <a href="https://docs.github.com/billing/managing-billing-for-your-github-account/upgrading-your-github-subscription">upgrade</a> your account.
    HTML

    SDN_RESTRICTION_TEMPLATE = T.let(<<~HTML.chomp, String)
      It appears this account may be subject to U.S. economic sanctions. \
      As a result, we are unable to provide services to the account. Please read about \
      <a href=#{GitHub.trade_controls_help_url} class="Link--inTextBlock">GitHub and Trade Controls</a> for more information.
    HTML

    PAID_ORG_ENFORCEMENT_MAIL_TEMPLATE = T.let(<<~HTML.chomp, String)
      #{US_SANCTIONED_REGION} As a result, \
      we are unable to provide private repository services and paid services for your account. \

      The restriction suspends access to private repository services and paid services, \
      such as availability of free or paid private repositories, secret gists, paid Action minutes, \
      Sponsors, and GitHub Marketplace services. For paid organizational accounts associated with sanctioned regions, \
      users may have limited access to their public repositories, which have been downgraded to archived read-only repositories.

      #{ORG_FILE_APPEAL_GENERIC} #{MORE_INFO}
    HTML

    GENERIC_FREE_ORG_TEMPLATE = T.let(<<~HTML.chomp, String)
      #{US_SANCTIONED_REGION} As a result, we are unable to \
      provide private repository services and paid services for your account. \
      GitHub has preserved, however, your access to <a href=#{GitHub.trade_controls_services_available_url}>certain free services for public repositories</a>. \

      #{ORG_FILE_APPEAL_GENERIC} #{MORE_INFO}
    HTML

    GENERIC_BILLING_TEMPLATE = T.let(<<~HTML.chomp, String)
      #{US_SANCTIONED_REGION} As a result, we are unable to \
      provide private repository services and paid services for your account. \
      GitHub has preserved, however, your access to <a href=#{GitHub.trade_controls_services_available_url}>certain free services for public repositories</a>. \

      #{ORG_FILE_APPEAL_GENERIC} #{MORE_INFO}
    HTML

    RESTRICTION_TEMPLATE_FOR_NON_ADMINS = T.let(<<~HTML.chomp, String)
      #{US_SANCTIONED_REGION_NON_ADMIN} As a result, we are unable to \
      provide private repository services and paid services. \
      GitHub has preserved, however, access to <a href=#{GitHub.trade_controls_services_available_url}>certain free services for public repositories</a>.
    HTML

    SANCTIONED_DOMAIN_TEMPLATE = T.let(<<~HTML.chomp, String)
      may be for an entity restricted under U.S. trade controls. Please see the <a href='#{GitHub.trade_controls_help_url}'>FAQ</a> for more information
    HTML

    SANCTIONED_DOMAIN_EMAIL_TEMPLATE = T.let(<<~HTML.chomp, String)
      Email #{SANCTIONED_DOMAIN_TEMPLATE}
    HTML

    ARCHIVED_REPO_TEMPLATE_FOR_ADMINS = T.let(<<~HTML.chomp, String)
      #{US_SANCTIONED_REGION} As a result, we are unable to \
      provide private repository services and paid services for your account. \
      GitHub has preserved, however, your access to <a href=#{GitHub.trade_controls_services_available_url}>certain free services for public repositories</a>.
    HTML

    FREE_PRIVATE_REPO_TEMPLATE = T.let(<<~HTML.chomp, String)
      #{UNABLE_TO_PROVIDE_ACCESS}
      #{US_SANCTIONED_REGION} As a result, we are unable to \
      provide private repository services and paid services for your account. \
      GitHub has preserved, however, your access to <a href=#{GitHub.trade_controls_services_available_url}>certain free services for public repositories</a>. \

      #{ORG_FILE_APPEAL_GENERIC} #{MORE_INFO}
    HTML

    REPO_DISABLED_FOR_NON_ADMINS_TEMPLATE = T.let(<<~HTML.chomp, String)
      #{RESTRICTION_TEMPLATE_FOR_NON_ADMINS}

      #{NON_ADMIN_MORE_INFO}
    HTML

    REPO_ARCHIVED_FOR_NON_ADMINS_GENERIC_TEMPLATE = T.let(<<~HTML.chomp, String)
      #{ARCHIVED}

      #{RESTRICTION_TEMPLATE_FOR_NON_ADMINS}
    HTML

    REPO_ARCHIVED_FOR_NON_ADMINS_TEMPLATE = T.let(<<~HTML.chomp, String)
      #{ARCHIVED} #{DUE_TO_LAW} paid GitHub organization services have been restricted.
      #{PAID_ORG_SERVICES_BASE}
    HTML

    REPO_ARCHIVED_FOR_ADMINS_TEMPLATE = T.let(<<~HTML.chomp, String)
      #{ARCHIVED} #{DUE_TO_LAW} paid GitHub organization and private repo services have been restricted.
      #{PAID_ORG_SERVICES_BASE}
    HTML

    REPO_ARCHIVED_FOR_ADMINS_GENERIC_TEMPLATE = T.let(<<~HTML.chomp, String)
      #{ARCHIVED}

      #{ARCHIVED_REPO_TEMPLATE_FOR_ADMINS}
    HTML

    ORGANIZATION_ACCOUNT_RESTRICTED = T.let(GitHub::HTMLSafeString.make(GENERIC_FREE_ORG_TEMPLATE), String)
    BILLING_ACCOUNT_RESTRICTED = T.let(GitHub::HTMLSafeString.make(GENERIC_BILLING_TEMPLATE), String)
    FREE_PRIVATE_REPO_WARNING = T.let(GitHub::HTMLSafeString.make(FREE_PRIVATE_REPO_TEMPLATE), String)
    PAID_ORG_ENFORCEMENT_MAIL = T.let(GitHub::HTMLSafeString.make(PAID_ORG_ENFORCEMENT_MAIL_TEMPLATE), String)
    ACCOUNT_RESTRICTED_GENERIC = T.let(GitHub::HTMLSafeString.make(GENERIC_RESTRICTION_TEMPLATE), String)
    UNKNOWN_ERROR_GENERIC = T.let("Sorry, we hit a problem with your request, please try again later. Thanks for your " \
      "patience.", String)
    ACCOUNT_RESTRICTED_GENERIC_NON_ADMIN = T.let(GitHub::HTMLSafeString.make(RESTRICTION_TEMPLATE_FOR_NON_ADMINS), String)
    ACCOUNT_SDN_RESTRICTED = T.let(GitHub::HTMLSafeString.make(SDN_RESTRICTION_TEMPLATE), String)
    SANCTIONED_DOMAIN = T.let(GitHub::HTMLSafeString.make(SANCTIONED_DOMAIN_TEMPLATE), String)
    SANCTIONED_DOMAIN_EMAIL = T.let(GitHub::HTMLSafeString.make(SANCTIONED_DOMAIN_EMAIL_TEMPLATE), String)
    REPO_DISABLED_FOR_NON_ADMINS = T.let(GitHub::HTMLSafeString.make(REPO_DISABLED_FOR_NON_ADMINS_TEMPLATE), String)
    REPO_ARCHIVED_FOR_NON_ADMINS_GENERIC = T.let(GitHub::HTMLSafeString.make(REPO_ARCHIVED_FOR_NON_ADMINS_GENERIC_TEMPLATE), String)
    REPO_ARCHIVED_FOR_NON_ADMINS = T.let(GitHub::HTMLSafeString.make(REPO_ARCHIVED_FOR_NON_ADMINS_TEMPLATE), String)
    REPO_ARCHIVED_FOR_ADMINS = T.let(GitHub::HTMLSafeString.make(REPO_ARCHIVED_FOR_ADMINS_TEMPLATE), String)
    REPO_ARCHIVED_FOR_ADMINS_GENERIC = T.let(GitHub::HTMLSafeString.make(REPO_ARCHIVED_FOR_ADMINS_GENERIC_TEMPLATE), String)
    RESTRICTED_FREE_ORG_ALLOWED = T.let(GitHub::HTMLSafeString.make(RESTRICTED_FREE_ORG_ALLOWED_TEMPLATE), String)
    ACCOUNT_SDN_SPAMMY = T.let(GitHub::HTMLSafeString.make(ACCOUNT_SDN_SPAMMY_TEMPLATE), String)

    # Trade screening constants

    TRADE_SCREENING_SUPPORT_URL = T.let(GitHub.contact_support_url, String)
    TRADE_SCREENING_DATA_ISSUE_TEMPLATE = T.let("We are sorry, but there appears to be an issue with the billing information. %s. If you have verified the information, please <a href=#{TRADE_SCREENING_SUPPORT_URL}>contact us</a>.", String)
    TRADE_SCREENING_DATA_ISSUE_NAME_TEMPLATE = T.let(TRADE_SCREENING_DATA_ISSUE_TEMPLATE % "Please verify the first and last name are complete and accurate", String)
    TRADE_SCREENING_DATA_ISSUE_ORG_TEMPLATE = T.let(TRADE_SCREENING_DATA_ISSUE_TEMPLATE % "Please verify the organization information is complete and accurate", String)
    TRADE_SCREENING_DATA_ISSUE_ADDRESS_TEMPLATE = T.let(TRADE_SCREENING_DATA_ISSUE_TEMPLATE % "Please verify the address is complete and accurate", String)
    TRADE_SCREENING_DATA_ISSUE_LEGAL_ID_TEMPLATE = T.let(TRADE_SCREENING_DATA_ISSUE_TEMPLATE % "Please verify the legal ID is complete and accurate", String)
    TRADE_SCREENING_DATA_ISSUE_OTHER_TEMPLATE = T.let(TRADE_SCREENING_DATA_ISSUE_TEMPLATE % "Please verify the information is complete and accurate", String)
    TRADE_SCREENING_PERMANENTLY_BLOCKED_NOTICE_TEMPLATE = T.let("We are sorry, but after reviewing we have determined that the billing information supplied is ineligible for transactions with GitHub due to government restrictions." \
    "<p><a href=#{GitHub.help_url}/articles/github-and-trade-controls>Learn more</a> about GitHub and trade control regulations.", String)

    TRADE_SCREENING_DATA_ISSUE_NAME = T.let(GitHub::HTMLSafeString.make(TRADE_SCREENING_DATA_ISSUE_NAME_TEMPLATE), String)
    TRADE_SCREENING_DATA_ISSUE_ORG = T.let(GitHub::HTMLSafeString.make(TRADE_SCREENING_DATA_ISSUE_ORG_TEMPLATE), String)
    TRADE_SCREENING_DATA_ISSUE_ADDRESS = T.let(GitHub::HTMLSafeString.make(TRADE_SCREENING_DATA_ISSUE_ADDRESS_TEMPLATE), String)
    TRADE_SCREENING_DATA_ISSUE_LEGAL_ID = T.let(GitHub::HTMLSafeString.make(TRADE_SCREENING_DATA_ISSUE_LEGAL_ID_TEMPLATE), String)
    TRADE_SCREENING_DATA_ISSUE_OTHER = T.let(GitHub::HTMLSafeString.make(TRADE_SCREENING_DATA_ISSUE_OTHER_TEMPLATE), String)
    TRADE_SCREENING_PERMANENTLY_BLOCKED_NOTICE = T.let(GitHub::HTMLSafeString.make(TRADE_SCREENING_PERMANENTLY_BLOCKED_NOTICE_TEMPLATE), String)
    RECORD_LINKING_SUCCESS = T.let("You have successfully linked your billing information with this organization.", String)
    RECORD_LINKING_ERROR = T.let("Error in linking your billing information with this organization.", String)

    # Delegates all methods to Notices, passing the message string through
    # a scrubber to replace <a> links with the inlined URL.
    module_function

    sig { params(method: Symbol, args: T.untyped).returns(String) }
    def notice_as_plaintext(method, *args)
      TextHelper.strip_tags_inlining_urls T.unsafe(Notices).__send__(method, *args)
    end

    sig { returns(String) }
    def free_organization_account_restricted
      ORGANIZATION_ACCOUNT_RESTRICTED
    end

    sig { returns(String) }
    def free_private_repo_warning
      FREE_PRIVATE_REPO_WARNING
    end

    sig { returns(String) }
    def sanctioned_domain_warning
      SANCTIONED_DOMAIN
    end

    sig { returns(String) }
    def sanctioned_domain_email_warning
      SANCTIONED_DOMAIN_EMAIL
    end

    sig { returns(String) }
    def billing_account_restricted
      BILLING_ACCOUNT_RESTRICTED
    end

    sig { returns(String) }
    def secret_gist_restricted
      ACCOUNT_RESTRICTED_GENERIC
    end

    # Strict newline formatting is required for the API
    sig { returns(String) }
    def organization_account_restricted
      <<~HTML
        #{DUE_TO_LAW} paid GitHub organization services have been restricted.

        #{PAID_ORG_SERVICES_SUSPENDED}

        #{MORE_INFO}
      HTML
    end

    sig { returns(String) }
    def organization_account_enforcement_mail
      PAID_ORG_ENFORCEMENT_MAIL
    end

    sig { returns(String) }
    def restricted_free_org_allowed_mail
      RESTRICTED_FREE_ORG_ALLOWED
    end

    sig { returns(String) }
    def organization_owned_repo_disabled
      <<~HTML
        #{DUE_TO_LAW} this repository has been disabled.

        #{PAID_ORG_SERVICES_SUSPENDED}

        #{MORE_INFO}
      HTML
    end

    sig { returns(String) }
    def organization_owned_repo_disabled_for_non_admins
      <<~HTML
        #{DUE_TO_LAW} this repository has been disabled.

        #{NON_ADMIN_MORE_INFO}
      HTML
    end

    sig { returns(String) }
    def organization_owned_repo_disabled_generic
      ACCOUNT_RESTRICTED_GENERIC
    end

    sig { returns(String) }
    def organization_owned_repo_disabled_for_non_admins_generic
      REPO_DISABLED_FOR_NON_ADMINS
    end

    sig { returns(String) }
    def organization_sdn_restricted
      ACCOUNT_SDN_RESTRICTED
    end

    sig { returns(String) }
    def organization_owned_repo_archived
      REPO_ARCHIVED_FOR_ADMINS
    end

    sig { returns(String) }
    def organization_owned_repo_archived_for_non_admins
      REPO_ARCHIVED_FOR_NON_ADMINS
    end

    sig { returns(String) }
    def organization_owned_repo_archived_for_non_admins_generic
      REPO_ARCHIVED_FOR_NON_ADMINS_GENERIC
    end

    sig { returns(String) }
    def organization_owned_repo_archived_generic
      REPO_ARCHIVED_FOR_ADMINS_GENERIC
    end

    sig { returns(String) }
    def archived_cta_for_non_admins
      <<~HTML
        #{NON_ADMIN_MORE_INFO}
      HTML
    end

    sig { returns(String) }
    def archived_cta_for_admins
      <<~HTML
        #{ORG_FILE_APPEAL_GENERIC} #{MORE_INFO}
      HTML
    end

    sig { returns(String) }
    def archived_cta_for_sdn_restricted_admins
      <<~HTML
        #{ORG_FILE_APPEAL_SDN_RESTRICTION_GENERIC} #{MORE_INFO}
      HTML
    end

    # Strict newline formatting is required for the API
    sig { returns(String) }
    def api_access_restricted
      <<~TEXT
        #{DUE_TO_LAW} we are unable to provide this access to this API. \
        #{MORE_INFO}
      TEXT
    end

    sig { returns(String) }
    def api_user_account_restricted_generic
      <<~TEXT
      #{US_SANCTIONED_REGION} As a result, \
      we are unable to provide private repository services and paid services for your \
      account. GitHub has preserved, however, your access to certain free services \
      for public repositories. If your account has been flagged in error, and you \
      are not located in or resident in a sanctioned region, please file an appeal. \
      Please read about GitHub and Trade Controls for more information.
      (#{GitHub.trade_controls_help_url})
      TEXT
    end

    sig { returns(String) }
    def api_org_invite_restricted_user
      <<~TEXT
        #{DUE_TO_LAW} we are unable to provide this feature for the invited user. \
        #{MORE_INFO}
      TEXT
    end

    sig { returns(String) }
    def billing_email_restriction_reason
      "Billing email TLD is sanctioned"
    end

    sig { returns(String) }
    def external_billing_email_restriction_reason
      "One of external billing emails TLD is sanctioned"
    end

    sig { returns(String) }
    def user_emails_restriction_reason
      "One of the user emails TLD is sanctioned"
    end

    sig { returns(String) }
    def profile_email_restriction_reason
      "Public profile email TLD is sanctioned"
    end

    sig { returns(String) }
    def org_member_linked_billing_info_warning
      "This member's billing information is linked to this organization. If the member is removed, you will need to update the payment information for this organization."
    end

    sig { returns(String) }
    def website_url_restriction_reason
      "Public profile website TLD is sanctioned"
    end

    sig { returns(String) }
    def trade_screening_customer_account_under_review
      "Sorry, there may be an issue with the billing information. We're looking into it and will get back to you within 48 hours. Thanks for your patience."
    end

    sig { returns(String) }
    def trade_screening_customer_account_under_review_for_less_than_2_days
      "There appears to be an issue with the billing information. We're looking into it and will send you an update within 48 " \
        "hours. Thank you for your patience."
    end

    sig { returns(String) }
    def trade_screening_customer_account_under_review_between_2_to_7_days
      "We are still investigating the issue with the billing information, and we will update you as soon as possible. Thank " \
        "you for your patience during this process. We are sorry for any inconvenience."
    end

    sig { returns(String) }
    def trade_screening_customer_account_permanently_blocked_after_review
      TRADE_SCREENING_PERMANENTLY_BLOCKED_NOTICE
    end

    sig { returns(String) }
    def trade_screening_customer_account_disabled
      "Your Customer account was not approved. Transactions for this customer are not allowed"
    end

    sig { returns(String) }
    def trade_screening_customer_account_ingestion_error
      "There appears to be an issue with the billing information, please verify the details are correct."
    end

    sig { returns(String) }
    def trade_screening_customer_account_data_issue_name_error
      TRADE_SCREENING_DATA_ISSUE_NAME
    end

    sig { returns(String) }
    def trade_screening_customer_account_data_issue_org_error
      TRADE_SCREENING_DATA_ISSUE_ORG
    end

    sig { returns(String) }
    def trade_screening_customer_account_data_issue_address_error
      TRADE_SCREENING_DATA_ISSUE_ADDRESS
    end

    sig { returns(String) }
    def trade_screening_customer_account_data_issue_legal_id_error
      TRADE_SCREENING_DATA_ISSUE_LEGAL_ID
    end

    sig { returns(String) }
    def trade_screening_customer_account_data_issue_other_error
      TRADE_SCREENING_DATA_ISSUE_OTHER
    end

    sig { returns(String) }
    def trade_screening_account_restricted_generic
      "Sorry, there may be an issue with the billing information. We're looking into it and will get back to you within 48 hours. Thanks for your patience."
    end

    sig { returns(String) }
    def org_api_delete_restricted
      "This GitHub organization is restricted from deletion."
    end

    sig { returns(String) }
    def trade_screening_account_spammy
      ACCOUNT_SDN_SPAMMY
    end

    sig { params(percent: T.any(Integer, Float), type: String).returns(String) }
    def percentage_restriction_reason(percent:, type:)
      "#{percent}% of #{type} are trade restricted"
    end

    # Strict newline formatting is required for the mailer.
    sig { returns(String) }
    def user_account_restricted
      <<~HTML
        #{DUE_TO_LAW} your GitHub account has been restricted.

        #{PAID_SERVICES_SUSPENDED}

        #{FILE_APPEAL}

        #{MORE_INFO}
      HTML
    end

    sig { returns(String) }
    def user_account_restricted_generic
      ACCOUNT_RESTRICTED_GENERIC
    end

    sig { returns(String) }
    def unknown_error_generic
      UNKNOWN_ERROR_GENERIC
    end

    sig { returns(String) }
    def org_invite_restricted
      <<~TEXT
        #{DUE_TO_LAW} we are unable to provide this feature.

        #{MORE_INFO}
      TEXT
    end

    sig { returns(String) }
    def org_restricted
      <<~TEXT
        #{DUE_TO_LAW} this GitHub organization has been restricted.

        #{NON_ADMIN_MORE_INFO}
      TEXT
    end

    sig { returns(String) }
    def org_restricted_repo_for_admins
      <<~HTML
        #{DUE_TO_LAW} paid GitHub organization services have been restricted.

        #{PAID_ORG_SERVICES_SUSPENDED} \
        #{MORE_INFO}
      HTML
    end

    sig { returns(String) }
    def org_restricted_repo_for_collaborators
      <<~HTML
        #{DUE_TO_LAW} this GitHub organization has been restricted. \
        #{MORE_INFO}
      HTML
    end

    sig { returns(String) }
    def repo_disabled
      <<~HTML
        #{DUE_TO_LAW} this repository has been disabled.

        #{PAID_SERVICES_SUSPENDED}

        #{FILE_APPEAL}

        #{MORE_INFO}
      HTML
    end

    sig { returns(String) }
    def repo_disabled_generic
      ACCOUNT_RESTRICTED_GENERIC
    end

    sig { params(type: String).returns(String) }
    def generic_prevent_toggle_to_private(type:)
      "Due to restrictions on this #{type}, you cannot change the visibility."
    end

    sig { params(type: String).returns(String) }
    def restricted_public_abilities_for(type:)
      "You may only use this #{type} for personal communications, and not for commercial purposes."
    end

    # use this message only when you need to communicate an issue with the account without further
    # expose of what trade restrictions are imposed.
    sig { params(owner_login: String).returns(String) }
    def private_repo_member_restriction(owner_login)
      "Please contact #{owner_login} to resolve the issue."
    end

    ##### Stafftools notices #####
    sig { params(owner_sdn_status: String).returns(String) }
    def terms_of_service_sdn_blocked_text(owner_sdn_status)
      "Account has commercial interaction restrictions (#{owner_sdn_status}), terms of service shouldn't be changed. Reach out to the #trade-compliance team for assistance."
    end

    sig { returns(String) }
    def stafftools_trade_screening_sales_managed
      "This account is managed through a sales account. Any change to trade screening must go through sales channels. Reach out to the #trade-compliance team for assistance."
    end
    ##### end Stafftools notices #####

    sig { returns(String) }
    def record_linking_success
      RECORD_LINKING_SUCCESS
    end

    sig { returns(String) }
    def record_linking_error
      RECORD_LINKING_ERROR
    end

    sig { returns(String) }
    def coupon_application_not_screened_notice
      "Please don't apply coupons to this account without checking with #legal first, as the account does not have a valid trade screened record."
    end
  end
end
