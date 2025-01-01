# typed: true
# frozen_string_literal: true

module SecurityCenter
  class PageComponent < ApplicationComponent
    extend T::Sig

    renders_one :header_section
    renders_one :main_section

    PERMISSIONS_DOC_HREF = "#{GitHub.help_url(ghec_exclusive: true)}/code-security/security-overview/about-security-overview#permission-to-view-data-in-security-overview"

    sig { returns(User) }; attr_reader :user
    sig { returns(Organization) }; attr_reader :organization
    sig { returns(Symbol) }; attr_reader :selected_tab
    sig { returns(T::Boolean) }; attr_reader :backfill_in_progress
    sig { returns(String) }; attr_reader :banner

    sig do
      params(
        user: User,
        organization: Organization,
        selected_tab: Symbol,
        backfill_in_progress: T::Boolean,
        banner: String,
      ).void
    end
    def initialize(
      user:,
      organization:,
      selected_tab:,
      backfill_in_progress: false,
      banner: "feedback-survey-banner"
    )
      @user = user
      @organization = organization
      @backfill_in_progress = backfill_in_progress
      @selected_tab = selected_tab
      @banner = banner
    end

    sig { returns(T::Boolean) }
    def show_feedback_survey?
      return false unless ::SecurityCenter::FeatureFlagHelper.security_center_feedback_link_enabled?(user, organization)
      return false unless banner == "feedback-survey-banner"
      !backfill_in_progress
    end

    sig { returns(T::Boolean) }
    def show_security_configs_banner?
      return false if GitHub.enterprise?
      banner == "security-configs-banner"
    end
  end
end
