# typed: true
# frozen_string_literal: true

class BusinessCampaignMailer < BusinessMailer

  self.mailer_name = "mailers/business_campaign"

  RESOURCE_CREATION_ELIGIBLE_COUNTRY_CODE = %w[US CA]

  # Public: Send welcome email to net new GHES enterprise account admins.
  #
  # business - Net new GHES enterprise account.
  #
  # Returns Mail.
  def welcome_net_new_enterprise_account_ghes(business)
    return unless business.enterprise_web_business_id.present?

    send_email = business.feature_flag_enabled_or_raise?(:ghes_receive_net_new_enterprise_account_email) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    @business = business
    @email_attributes = email_attributes

    if send_email
      premail(
        from: github_noreply,
        bcc: business_emails(@business),
        subject: @email_attributes[:subject],
      )
    end

    trigger_customer_success_campaign_events(send_email, business, @email_attributes[:campaign_codes][:email_campaign], :welcome)
  end

  # Public: Send a welcome email to net new enterprise account admins.
  #
  # business - Net new enterprise account.
  #
  # Returns Mail.
  def welcome_net_new_enterprise_account(business)
    # Return if the business is associated with a GHES installation.
    return if business.enterprise_web_business_id.present?

    send_email = business.feature_flag_enabled_or_raise?(:ghec_receive_net_new_enterprise_account_email) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    @business = business
    @email_attributes = email_attributes

    if send_email
      premail(
        from: github_noreply,
        bcc: business_emails(@business),
        subject: @email_attributes[:subject],
      )
    end

    trigger_customer_success_campaign_events(send_email, business, @email_attributes[:campaign_codes][:email_campaign], :welcome)
  end

  # Public: Send a welcome email to net new enterprise account admins, variation A.
  #
  # business - Net new enterprise account.
  #
  # Returns Mail.
  def welcome_net_new_enterprise_account_variation_a(business)
    # Return if the business is associated with a GHES installation.
    return if business.enterprise_web_business_id.present?

    send_email = business.feature_flag_enabled_or_raise?(:ghec_receive_net_new_enterprise_account_email) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    @business = business
    @email_attributes = email_attributes(variation: :a)
    @email_attributes_text = email_attributes

    if send_email
      premail(
        from: github_noreply,
        bcc: business_emails(@business),
        subject: @email_attributes[:subject],
      )
    end

    trigger_customer_success_campaign_events(send_email, business, @email_attributes[:campaign_codes][:email_campaign], :welcome)
  end

  # Public: Send a welcome email to net new enterprise account admins, variation B.
  #
  # business - Net new enterprise account.
  #
  # Returns Mail.
  def welcome_net_new_enterprise_account_variation_b(business)
    # Return if the business is associated with a GHES installation.
    return if business.enterprise_web_business_id.present?

    send_email = business.feature_flag_enabled_or_raise?(:ghec_receive_net_new_enterprise_account_email) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
    @business = business
    @email_attributes = email_attributes(variation: :b)
    @email_attributes_text = email_attributes

    if send_email
      premail(
        from: github_noreply,
        bcc: business_emails(@business),
        subject: @email_attributes[:subject],
      )
    end

    trigger_customer_success_campaign_events(send_email, business, @email_attributes[:campaign_codes][:email_campaign], :welcome)
  end

  private

  def trigger_customer_success_campaign_events(email_sent, business, campaign, campaign_stage)
    business.owners.each do |user|
      GlobalInstrumenter.instrument("customer_success_campaign.email", {
        user: user,
        business: business,
        email_sent: email_sent,
        campaign_name: campaign,
        campaign_email_name: campaign_stage
      })
    end
  end

  # Private: Returns a hash of email campaign attributes
  def email_attributes_hash
    {
      ghes: {
        campaign_codes: {
          email_source: :"ghes-net-new-welcome",
          utm_campaign: :"2024q1-em-GHESwelcome",
          email_campaign: :post_purchase_ghes_admin,
        },
        ghio_links: {
          header_image: "AAlre8f",
          comprehensive_guide: "AAm7gvv",
          dive_deeper_with_docs: "AAlre8g",
          community_discussions_premium: "AApbzsj",
          community_discussions: "AAp4a0k",
          github_support: "AAm7wb9",
          github_support_premium_plus: "AAlp936",
          github_support_premium: "AAlp936",
        },
        subject: "[GitHub] GitHub Enterprise: start building like the best 🚀",
      },
      emu: {
        campaign_codes: {
          email_source: :"ghec-trial-upgrade-emu",
          utm_campaign: :"2024q1-em-GHEemuwelcome",
          email_campaign: :post_purchase_emu_admin,
        },
        ghio_links: {
          header_image: "AAq2kkz",
          emu_guide: "AApbzsn",
          comprehensive_guide: "",
          dive_deeper_with_docs: "AApxn48",
          community_discussions_premium: "AAq2kl0",
          community_discussions: "AAq2sau",
          github_support: "AAq2kl1",
          github_support_premium_plus: "AApx7on",
          github_support_premium: "AAq37qa",
        },
        subject: "[GitHub] GitHub Enterprise: start building like the best 🚀",
      },
      resouce_enabled: {
        campaign_codes: {
          email_source: :"ghec-trial-upgrade-with-onboarding-resources",
          utm_campaign: :"2024q4-em-GHECwelcome-onboarding-resource",
          email_campaign: :post_purchase_ghec_admin_with_onboarding_resources,
        },
        ghio_links: {
          onboarding_resources: "onboarding-resources?enterprise_id=#{@business.id}",
          header_image: "AApvhy9",
          emu_guide: "",
          comprehensive_guide: "AApvhya",
          dive_deeper_with_docs: "AApvhyb",
          community_discussions_premium: "AApwkj4",
          community_discussions: "AApx7og",
          github_support: "AApws8w",
          github_support_premium_plus: "AApvhyc",
          github_support_premium: "AApwzyo",
        },
        subject: "[GitHub] GitHub Enterprise: start building like the best 🚀",
        cta_link: "#{GitHub.support_url}/success/onboarding-resources",
        cta_params: {
          enterprise_id: @business.id,
          utm_source: :product,
          utm_medium: :email,
          utm_campaign: :"2024q4-em-GHECwelcome-onboarding-resource",
        },
      },
      resouce_enabled_a: {
        campaign_codes: {
          email_source: :"ghec-trial-upgrade-with-onboarding-resources",
          email_campaign: :post_purchase_ghec_admin_with_onboarding_resources_a,
        },
        ghio_links: {
          header_image: "AAqekoh",
          github_support: "AAqfuz5",
          github_support_premium_plus: "AAqfuz6",
          github_support_premium: "AAq9fi1",
        },
        subject: "Welcome to GitHub Enterprise: Let's build from here 🚀",
        cta_link: "#{GitHub.support_url}/success/onboarding-resources",
        cta_params: {
          enterprise_id: @business.id,
          utm_source: :product,
          utm_medium: :email,
          utm_campaign: :"ghec-welcome-onboarding-resources-success-repo-cta",
        },
      },
      resouce_enabled_b: {
        campaign_codes: {
          email_source: :"ghec-trial-upgrade-with-onboarding-resources",
          email_campaign: :post_purchase_ghec_admin_with_onboarding_resources_b,
        },
        ghio_links: {
          header_image: "AAqese8",
          github_support: "AAqg2ox",
          github_support_premium_plus: "AAqfuz7",
          github_support_premium: "AAq902f",
        },
        subject: "Welcome to GitHub Enterprise: Let's build from here 🚀",
        cta_link: "#{GitHub.support_url}/success/onboarding-resources",
        cta_params: {
          enterprise_id: @business.id,
          utm_source: :product,
          utm_medium: :email,
          utm_campaign: :"ghec-welcome-onboarding-resources-success-repo-cta-gif",
        },
      },
      resouce_disabled: {
        campaign_codes: {
          email_source: :"ghec-trial-upgrade",
          utm_campaign: :"2024q1-em-GHEwelcome",
          email_campaign: :post_purchase_ghec_admin,
        },
        ghio_links: {
          header_image: "AAm0lyb",
          emu_guide: "",
          comprehensive_guide: "AAlr6h8",
          dive_deeper_with_docs: "AAlpogr",
          community_discussions_premium: "AAp4a0j",
          community_discussions: "AAp54vm",
          github_support: "AAlpogs",
          github_support_premium_plus: "AAlpgqx",
          github_support_premium: "AAlpgqx",
        },
        subject: "[GitHub] GitHub Enterprise: start building like the best 🚀",
      }
    }
  end

  # Private: Returns a hash of gh.io short links based on the customer's segment
  #
  # business - an enterprise account
  #
  # Returns hash of short links
  def email_attributes(variation: nil)
    if variation == :a
      attributes = email_attributes_hash[:resouce_enabled_a]
    elsif variation == :b
      attributes = email_attributes_hash[:resouce_enabled_b]
    elsif @business.enterprise_web_business_id.present?
      attributes = email_attributes_hash[:ghes]
    elsif @business.enterprise_managed?
      attributes = email_attributes_hash[:emu]
    elsif @business.resource_creation_enabled?
      attributes = email_attributes_hash[:resouce_enabled]
    else
      attributes = email_attributes_hash[:resouce_disabled]
    end

    attributes[:ghio_links][:header_image] = "AAqfuz4" if ENV["RAILS_ENV"] == "development"

    if attributes[:cta_link]
      uri = URI.parse(attributes[:cta_link])
      uri.query = attributes[:cta_params].to_param
      attributes[:cta_link] = uri.to_s
    end

    attributes[:ghio_links].each do |k, v|
      attributes[:ghio_links][k] = "https://gh.io/#{v}"
    end

    attributes
  end
end
