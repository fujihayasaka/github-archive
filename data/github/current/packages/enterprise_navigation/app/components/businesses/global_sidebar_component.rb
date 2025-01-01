# typed: strict
# frozen_string_literal: true

class Businesses::GlobalSidebarComponent < ApplicationComponent

  # To add links see https://github.com/github/meao/wiki/Enterprise-Navigation

  include EnterpriseNavigation::Links::All
  include EnterpriseNavigation::Links::SharedDependency

  sig { returns T.nilable(Business) }
  attr_reader :business

  sig { returns Symbol }
  attr_reader :sidebar_section

  sig { returns T.nilable(User) }
  attr_reader :user

  sig { returns T::Hash[Symbol, T.untyped] }
  attr_reader :system_arguments

  DEFAULT_SECTION = T.let(:none, Symbol)
  SECTION_VALUES = T.let([:people, :policies, :identity_provider, :github_connect, :code_security, :billing_and_licensing, :settings, :insights, :none].freeze, T::Array[Symbol])

  sig do
    params(
      user: T.nilable(User),
      business: T.nilable(Business),
      selected_link: T.nilable(T.any(String, Symbol)),
      sidebar_section: T.nilable(Symbol),
      system_arguments: Primer::SystemArgumentsValue).void
  end
  def initialize(user: nil, business: nil, selected_link: nil, sidebar_section: DEFAULT_SECTION, **system_arguments)
    sidebar_section = DEFAULT_SECTION if sidebar_section.nil?
    @sidebar_section = T.let(fetch_or_fallback(SECTION_VALUES, sidebar_section, DEFAULT_SECTION), Symbol)
    @user = user
    @business = business
    @selected_link = selected_link
    @system_arguments = system_arguments
    # for styling see app/assets/stylesheets/bundles/github/businesses.scss
    @system_arguments[:classes] = class_names("business-global-sidebar", @system_arguments[:classes])
  end

  sig { returns T::Boolean }
  def render?
    return false unless @user && @business
    return false if sidebar_component.nil?
    true
  end

  sig { returns T.nilable(Businesses::SidebarComponent) }
  memoize def sidebar_component
    with_database_error_fallback(fallback: nil) do
      case @sidebar_section
      when :people
        Businesses::SidebarComponent.new(
          title: "People",
          user: @user,
          business: @business,
          groups: people_menu_groups,
          selected_link: @selected_link,
          test_selector: "people-sidebar",
        )
      when :policies
        Businesses::SidebarComponent.new(
          title: "Policies",
          user: @user,
          business: @business,
          groups: policies_menu_groups,
          selected_link: @selected_link,
          test_selector: "policies-sidebar",
        ) unless downgraded_to_free_plan?
      when :identity_provider
        Businesses::SidebarComponent.new(
          title: "Identity Provider",
          user: @user,
          business: @business,
          groups: identity_provider_groups,
          selected_link: @selected_link,
          test_selector: "identity-provider-sidebar",
        ) if show_identity_provider_sidebar?
      when :code_security
        Businesses::SidebarComponent.new(
          title: "Security",
          user: @user,
          business: @business,
          groups: code_security_groups,
          selected_link: @selected_link,
          test_selector: "security-sidebar",
        ) if show_code_security_sidebar?
      when :billing_and_licensing
        Businesses::SidebarComponent.new(
          title: "Billing & Licensing",
          user: @user,
          business: @business,
          groups: billing_menu_groups,
          selected_link: @selected_link,
          test_selector: "billing-and-licensing-sidebar",
        ) if show_billing_and_licensing_sidebar?
      when :settings
        Businesses::SidebarComponent.new(
          title: "Settings",
          user: @user,
          business: @business,
          groups: settings_menu_groups,
          selected_link: @selected_link,
          test_selector: "settings-sidebar",
        )
      when :insights
        Businesses::SidebarComponent.new(
          title: "Insights",
          user: @user,
          business: @business,
          groups: insights_menu_groups,
          selected_link: @selected_link,
          test_selector: "insights-sidebar",
        )
      else
        nil
      end
    end
  end

  sig { returns T::Boolean }
  memoize def downgraded_to_free_plan?
    GitHub.billing_enabled? && business&.downgraded_to_free_plan? || false
  end

  sig { returns T::Boolean }
  def show_code_security_sidebar?
    return false if basic_account?
    return false if @business&.downgraded_to_free_plan?
    code_security_menu_items.flatten.present?
  end

  sig { returns T::Boolean }
  def show_billing_and_licensing_sidebar?
    @business&.customer&.billed_via_billing_platform? && (
      business_owner? || business_org_owner? || business_billing_manager?) || false
  end

  sig { returns T::Boolean }
  def show_identity_provider_sidebar?
    @business&.enterprise_managed_user_enabled? || false
  end
end
return
