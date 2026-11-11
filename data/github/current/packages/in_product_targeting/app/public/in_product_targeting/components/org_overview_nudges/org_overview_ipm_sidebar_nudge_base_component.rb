# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module OrgOverviewNudges
      # Base component for IPM nudges on the Org Overview right sidebar.
      # Mounts the React `org-overview-sidebar-nudge` partial — visual rendering lives in
      # github/github-ui (packages/in-product-targeting/org-overview-sidebar-nudge).
      #
      # Subclasses must define:
      # - NUDGE_CATEGORY, NUDGE_ID constants
      # And implement:
      # - eligible_for_nudge?
      # - nudge_category, nudge_id
      # - nudge_title, nudge_description
      # - nudge_cta, nudge_cta_action
      # - nudge_date
      # - nudge_topics
      # - nudge_image_path_dark, nudge_image_path_light
      # - nudge_image_alt_dark, nudge_image_alt_light
      # Optional (override one or the other, not both):
      # - nudge_cta_href: return a direct URL string; if nil, destination_path is used instead
      # - use_dismiss_and_redirect + DESTINATION_PATHS entry: tracks dismiss server-side before redirect
      class OrgOverviewIpmSidebarNudgeBaseComponent < ApplicationComponent
        include ApplicationComponent::Rescuable
        extend T::Helpers
        include InProductTargeting::Components::Concerns::DestinationPath

        # Defensive: a render error must never break the org overview page.
        rescue_from StandardError, with: :nothing

        NUDGE_LOCATION = "org_overview"
        NUDGE_GROUP = :engage
        PARTIAL_NAME = T.let("org-overview-sidebar-nudge", String)

        abstract!

        sig do
          params(
            organization: Organization
          ).void
        end
        def initialize(organization:)
          @organization = T.let(organization, Organization)
        end

        sig { returns(T.nilable(String)) }
        def call
          return unless render?

          # Leading marker span carrying the data-test-selector — the existing
          # Capybara integration tests look it up with assert_select. We emit
          # it on the Ruby side so the selector exists in the rendered HTML
          # regardless of whether the React partial's SSR succeeds or raises
          # (e.g. while the github-ui bundle is mid-deploy).
          marker = content_tag(:span, nil, "data-test-selector" => nudge_category)
          marker + react_partial_output
        end

        sig { returns(ActiveSupport::SafeBuffer) }
        def react_partial_output
          rendered = render_react_partial(name: PARTIAL_NAME, props: react_props)
          rendered.is_a?(ActiveSupport::SafeBuffer) ? rendered : ActiveSupport::SafeBuffer.new
        rescue StandardError => e
          Rails.logger.warn("[OrgOverviewIpmSidebarNudge] React partial render failed: #{e.class}: #{e.message}")
          ActiveSupport::SafeBuffer.new
        end

        private

        sig { returns(T::Boolean) }
        def render?
          !!(logged_in? && eligible_for_nudge?)
        end

        sig { returns(Organization) }
        attr_reader :organization

        sig { abstract.returns(T::Boolean) }
        def eligible_for_nudge?
        end

        sig { overridable.returns(T.nilable(String)) }
        def nudge_cta_href
          nil
        end

        # Abstract methods for nudge configuration - subclasses must override
        sig { abstract.returns(String) }
        def nudge_category
        end

        sig { abstract.returns(Symbol) }
        def nudge_id
        end

        # Abstract methods for nudge content - subclasses must override
        sig { abstract.returns(String) }
        def nudge_title
        end

        sig { overridable.returns(String) }
        def nudge_group
          NUDGE_GROUP.to_s
        end

        sig { abstract.returns(String) }
        def nudge_description
        end

        sig { abstract.returns(String) }
        def nudge_cta
        end

        sig { abstract.returns(String) }
        def nudge_cta_action
        end

        sig { abstract.returns(String) }
        def nudge_date
        end

        sig { abstract.returns(T::Array[String]) }
        def nudge_topics
        end

        sig { abstract.returns(String) }
        def nudge_image_path_dark
        end

        sig { abstract.returns(String) }
        def nudge_image_path_light
        end

        sig { abstract.returns(String) }
        def nudge_image_alt_light
        end

        sig { abstract.returns(String) }
        def nudge_image_alt_dark
        end

        sig { overridable.returns(String) }
        def destination_key
          nudge_id.to_s
        end

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        def destination_url_params
          {
            destination_key: destination_key,
            organization_id: organization.id,
            notice: nudge_id,
            group: nudge_group,
            organization_login: organization.display_login,
          }
        end

        sig { override.returns(T.nilable(Business)) }
        def destination_business
          organization.business
        end

        sig { returns(::Copilot::Organization) }
        memoize def org_copilot
          ::Copilot::Organization.new(organization)
        end

        # Common eligibility checks shared across subclasses
        sig { returns(T::Boolean) }
        def base_eligibility_checks_are_satisfied?
          return false unless current_user.feature_flag_enabled?(nudge_id, default: false)
          return false unless current_user.subscribed_to_in_product_messages?
          return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise? || current_user.is_enterprise_managed?
          return false unless ::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", organization_id: organization.id)
          business = organization.business
          return false if business && !::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", business_id: business.id)
          return false if current_user.dismissed_organization_notice?(nudge_id.to_s, organization)

          true
        end

        # Serializable props passed to the React `org-overview-sidebar-nudge` partial.
        # Mirrors OrgOverviewSidebarNudgeProps in
        # github/github-ui/packages/in-product-targeting/org-overview-sidebar-nudge/OrgOverviewSidebarNudge.tsx.
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def react_props
          {
            title: nudge_title,
            dateLabel: nudge_date,
            imagePathLight: image_path(nudge_image_path_light),
            imagePathDark: image_path(nudge_image_path_dark),
            imageAltLight: nudge_image_alt_light,
            imageAltDark: nudge_image_alt_dark,
            topics: nudge_topics,
            ctaTitle: nudge_cta,
            ctaHref: nudge_cta_href || destination_path,
            dismissPath: organization_dismiss_notice_path(
              notice: nudge_id,
              organization_id: organization.id,
              group: nudge_group,
            ),
            analytics: {
              category: nudge_category,
              group: nudge_group,
              location: NUDGE_LOCATION,
              ctaAction: nudge_cta_action,
              organizationId: organization.id,
              plan: organization.plan.name,
            },
            testSelector: nudge_category,
          }
        end
      end
    end
  end
end
