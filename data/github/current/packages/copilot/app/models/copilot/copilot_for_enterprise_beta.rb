# typed: true
# frozen_string_literal: true

module Copilot
  class CopilotForEnterpriseBeta
    attr_reader :feature_slug, :feature_name, :waitlist,
                :survey, :survey_choice_detail_links, :preview_terms,
                :onboard_job
    FEATURE_NAME = Copilot::ENTERPRISE_PRODUCT_NAME
    BULK_ONBOARD_BATCH_SIZE = 500
    DetailLink = Struct.new(:text, :url, keyword_init: true)

    def initialize
      @feature_slug = "copilot_for_enterprise"
      @feature_name = "#{FEATURE_NAME}"
      @waitlist = EarlyAccessMembership.copilot_for_enterprise_waitlist
      @survey = Copilot::CopilotForEnterpriseBetaWaitlistSurvey.find_survey
      @onboard_job = Copilot::CopilotForEnterpriseBetaOnboardJob
      @survey_choice_detail_links = {}.with_indifferent_access
      @preview_terms = DetailLink.new(
        text: "the pre-release terms",
        url: "https://docs.github.com/site-policy/github-terms/github-copilot-pre-release-license-terms"
      )
    end

    def extra_columns(memberships)
      @counts_by_member ||= begin
        EarlyAccessMembership
          .copilot_for_enterprise_waitlist
          .where(can_onboard: false)
          .group(:member_id)
          .count
      end

      @adminable_by_member ||= begin
        memberships.map do |membership|
          member = membership.member
          next unless member && membership.actor
          [member.id, member.adminable_by?(membership.actor).to_s]
        end.compact.to_h
      end

      [
        {
          header: "User requests",
          get_content: ->(member) { @counts_by_member[member.id] || 0 }
        },
        {
          header: "Signed up by admin?",
          get_content: ->(member) { @adminable_by_member[member.id] || "unknown" }
        }
      ]
    end
  end
end
