# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module OrgOverviewNudges
      class OrgOverviewRoadmapWebinar2026Q2ApacNudgeComponent < OrgOverviewIpmSidebarNudgeBaseComponent
        include InProductTargeting::NudgeConcern

        NUDGE_ID         = T.let(:general_ipm_roadmap_webinar_2026_q2_nudge_apac, Symbol)
        NUDGE_CATEGORY   = T.let("general_ipm_roadmap_webinar_2026_q2_nudge_apac", String)
        ACTIVE_START     = T.let(Date.new(2026, 6, 8), Date)
        ACTIVE_END       = T.let(Date.new(2026, 6, 23), Date)

        sig { override.returns(T::Boolean) }
        def eligible_for_nudge?
          return false unless base_eligibility_checks_are_satisfied?
          return false unless organization.adminable_by?(current_user)

          business = organization.business
          if business
            return false if is_business_in_active_dfd_trial?(business)
            return false if business.trial_expired?
          end

          today = Time.now.utc.to_date
          return false unless (today >= ACTIVE_START && today <= ACTIVE_END) || Rails.env.development?
          return false unless InProductTargeting::GeoRegion.in_apac?(T.cast(request, ActionDispatch::Request).remote_ip) ||
            Rails.env.development?

          true
        end

        sig { override.returns(T::Boolean) }
        def use_dismiss_and_redirect = true

        sig { override.returns(String) }
        def nudge_category = NUDGE_CATEGORY

        sig { override.returns(Symbol) }
        def nudge_id = NUDGE_ID

        sig { override.returns(String) }
        def nudge_title = "GitHub Product Roadmap – Q2 2026"

        # Required by the base class interface but not rendered in the org overview template.
        sig { override.returns(String) }
        def nudge_description = "GitHub Product Roadmap – Q2 2026"

        sig { override.returns(String) }
        def nudge_cta = "Register for the webinar"

        sig { override.returns(String) }
        def nudge_cta_action = "register"

        sig { override.returns(String) }
        def nudge_date = "TUESDAY, JUNE 23"

        sig { override.returns(T::Array[String]) }
        def nudge_topics = ["What's new and what's coming next", "How to secure and govern AI at scale", "Rise of connected, agent workflows"]

        # Both paths point to the same physical asset — design confirmed a single image
        # works for both themes (see github/in-product-messaging#542).
        sig { override.returns(String) }
        def nudge_image_path_dark = "modules/org_overview/promos/org_overview_roadmap_webinar_2026_q2/webinar-dark.png"

        sig { override.returns(String) }
        def nudge_image_path_light = "modules/org_overview/promos/org_overview_roadmap_webinar_2026_q2/webinar-light.png"

        sig { override.returns(String) }
        def nudge_image_alt_dark = ""

        sig { override.returns(String) }
        def nudge_image_alt_light = ""
      end
    end
  end
end
