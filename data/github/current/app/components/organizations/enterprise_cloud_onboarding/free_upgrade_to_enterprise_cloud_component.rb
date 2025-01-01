# typed: strict
# frozen_string_literal: true

class Organizations::EnterpriseCloudOnboarding::FreeUpgradeToEnterpriseCloudComponent < ApplicationComponent
  extend T::Sig

  sig { returns(T.untyped) }
  attr_reader :system_arguments

  sig { params(ref_loc: String, system_arguments: T.untyped).void }
  def initialize(ref_loc:, **system_arguments)
    @ref_loc = ref_loc
    @system_arguments = system_arguments
  end

  sig { returns(String) }
  def learn_more_link
    render(Primer::Beta::Link.new(
      href: "#{GitHub.help_url}/admin/overview/creating-an-enterprise-account",
      classes: "Link--inTextBlock",
      data: analytics_click_attributes(
        category: "entacct_migration",
        action: "click_to_learn_more_about_enterprise_accounts",
        label: "ref_loc:#{@ref_loc};ref_cta:learn_more_about_enterprise_accounts"
      ))
    ) { "Learn more about enterprise accounts" }
  end

  sig { returns(String) }
  def enterprise_cloud_plan_link
    render(Primer::Beta::Link.new(
      href: "#{GitHub.help_url}/get-started/learning-about-github/githubs-plans#github-enterprise",
      classes: "Link--inTextBlock",
      data: analytics_click_attributes(
        category: "entacct_migration",
        action: "click_to_learn_more_about_enterprise_cloud_plan",
        label: "ref_loc:#{@ref_loc};ref_cta:enterprise_cloud_plan"
      ))
    ) { "Enterprise Cloud plan" }
  end

  sig { returns(String) }
  def organization_account_link
    render(Primer::Beta::Link.new(
      href: "#{GitHub.help_url}/get-started/learning-about-github/types-of-github-accounts#organization-accounts",
      classes: "Link--inTextBlock",
      data: analytics_click_attributes(
        category: "entacct_migration",
        action: "click_to_learn_more_about_organization_accounts",
        label: "ref_loc:#{@ref_loc};ref_cta:organization_account"
      ))
    ) { "organization account" }
  end

  sig { returns(String) }
  def enterprise_account_link
    render(Primer::Beta::Link.new(
      href: "#{GitHub.help_url}/get-started/learning-about-github/types-of-github-accounts#enterprise-accounts",
      classes: "Link--inTextBlock",
      data: analytics_click_attributes(
        category: "entacct_migration",
        action: "click_to_learn_more_about_enterprise_accounts",
        label: "ref_loc:#{@ref_loc};ref_cta:enterprise_account"
      ))
    ) { "enterprise account" }
  end
end
