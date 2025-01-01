# typed: strict
# frozen_string_literal: true

module Copilot
  class ExtensionsBeta
    extend T::Sig
    include GitHub::Memoizer

    FEATURE_SLUG = "copilot_extension_access"
    DetailLink = Struct.new(:text, :url, keyword_init: true)

    sig { returns(DetailLink) }
    def preview_terms
      DetailLink.new(
        text: "the pre-release terms",
        url: "https://docs.github.com/site-policy/github-terms/github-copilot-pre-release-license-terms"
      )
    end

    sig { returns(Survey) }
    memoize def survey
      Copilot::ExtensionsBetaWaitlistSurvey.find_or_create_survey!
    end

    sig { returns(String) }
    def feature_name
      "Copilot Extensions"
    end

    sig { returns(String) }
    def feature_slug
      FEATURE_SLUG
    end

    sig { returns(T.untyped) }  # rubocop:disable Sorbet/ForbidTUntyped
    def waitlist
      EarlyAccessMembership.copilot_extensions_waitlist
    end

    sig { returns(T.class_of(Copilot::ExtensionsBetaOnboardJob)) }
    def onboard_job
      Copilot::ExtensionsBetaOnboardJob
    end

    sig do
      params(memberships: T::Array[EarlyAccessMembership]).returns([
        { header: String, get_content: T.proc.params(arg0: T.untyped).returns(T.untyped) }, # rubocop:disable Sorbet/ForbidTUntyped
        { header: String, get_content: T.proc.params(arg0: T.untyped).returns(T.untyped) }  # rubocop:disable Sorbet/ForbidTUntyped
      ])
    end
    def extra_columns(memberships)
      counts_by_member ||= begin
        EarlyAccessMembership
          .copilot_extensions_waitlist
          .where(can_onboard: false)
          .group(:member_id)
          .count
      end

      adminable_by_member ||= begin
        memberships.map do |membership|
          member = membership.member
          next unless member && membership.actor
          [member.id, member.adminable_by?(membership.actor).to_s]
        end.compact.to_h
      end

      [
        {
          header: "Member type",
          get_content: ->(member) { member.class.name }
        },
        {
          header: "User requests",
          get_content: ->(member) { counts_by_member[member.id] || 0 }
        },
        {
          header: "Signed up by admin?",
          get_content: ->(member) { adminable_by_member[member.id] || "unknown" }
        }
      ]
    end
  end
end
