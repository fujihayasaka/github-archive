# typed: true
# frozen_string_literal: true

module OrgOverviewHelper
  def top_right_marketing_promos(context)
    current_user = context[:current_user]
    current_organization = context[:current_organization]
    request = context[:request]
    [
      {
          feature: :org_overview_roadmap_webinar_2025_q3_nudge,
          notice: :org_overview_roadmap_webinar_2025_q3_nudge,
          partial: "orgs/org_overview_roadmap_webinar_2025_q3/org_overview_roadmap_webinar_2025_q3_pre_event",
          extra_condition: -> {
            # this is redundant with a few lines earlier but is required to ensure the test suite doesn't complain
            return false unless current_user.feature_flag_enabled?(:org_overview_roadmap_webinar_2025_q3_nudge, default: false)

            # Don't show the nudge if the user is an enterprise managed user or in proxima
            return false if GitHub.multi_tenant_enterprise? || current_user&.is_enterprise_managed? || GitHub.enterprise?

            # Don't show the nudge if the user has opted out of in-product messaging
            return false unless current_user.subscribed_to_in_product_messages?

            # Only show for users in targeted countries
            return false unless %w[FR GB DE US].include?(GitHub::Location.look_up(request.remote_ip)[:country_code]) || Rails.env.development?

            # Only show for Team org admins or Enterprise admins

            return false unless (
              # A GitHub team admin of the current org
              (current_organization&.adminable_by?(current_user) && current_organization&.plan.name == GitHub::Plan.business.name) ||

              # A GHEC admin of the enterprise the current org is in
              current_organization&.business&.owner?(current_user)
            )

            true
          },
        },
    ]
  end
end
