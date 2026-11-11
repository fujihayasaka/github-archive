# typed: strict
# frozen_string_literal: true

class Profiles::Organization::GhasTrialBannerComponent < ApplicationComponent
  include GlobalNavigationHelper
  include AdvancedSecurityEntrypointHelper
  include ApplicationComponent::Rescuable

  rescue_from StandardError, with: :nothing

  NOTICE_NAME = "ghas_trial_upsell_banner"
  LEARN_MORE_URL = "https://resources.github.com/security/tools/ghas-trial/"

  sig { returns(T.nilable(::Organization)) }
  attr_reader :organization

  sig { returns(T.nilable(User)) }
  attr_reader :user

  sig { returns(Symbol) }
  attr_reader :display_mode

  sig { params(organization: T.nilable(::Organization), user: T.nilable(User), display_mode: T.nilable(Symbol)).void }
  def initialize(organization:, user:, display_mode: nil)
    @organization = organization
    @user = user
    begin
      @display_mode = T.let(display_mode || get_display_mode, Symbol)
    rescue StandardError
      # rescue_from helper doesn't appear to work if error is thrown in the initalize call
      @display_mode = :do_not_show
    end
  end

  private

  sig { returns(String) }
  def dismiss_notice
    dismiss_org_notice_path(T.must(@organization), input: { organizationId: T.must(@organization).id, notice: NOTICE_NAME })
  end

  sig { returns(String) }
  def learn_more_link
    render(Primer::Beta::Link.new(
      href: LEARN_MORE_URL,
      font_size: 5,
      data: analytics_click_attributes(
        category: "GHAS Information",
        action: "click to learn more about ghas",
        label: "location:org_overview"
      ))
    ) { "GitHub Advanced Security" }
  end

  sig { returns(T::Boolean) }
  def dismissed_less_than_90_days?
    return false unless T.must(@user).dismissed_organization_notice?(NOTICE_NAME, @organization)
    (Time.now - 90.days) < T.must(@user).notice_dismissed_at(NOTICE_NAME, @organization)
  end

  sig { returns(T::Boolean) }
  def render?
    return false if display_mode == :do_not_show
    return false if dismissed_less_than_90_days?

    instrument_banner_viewed

    true
  end

  sig { returns(T::Boolean) }
  def show_self_serve_cta?
    display_mode == :self_serve
  end

  sig { void }
  def instrument_banner_viewed
    GlobalInstrumenter.instrument("analytics.event",
      category: "ghas_trial_eligibility",
      action: "org_overview_banner_viewed",
      label: T.must(@organization).id.to_s,
    )
  end

  sig { returns(Symbol) }
  memoize def get_display_mode
    show_advanced_security_entrypoint?(organization: organization, user: user)
  end

end
