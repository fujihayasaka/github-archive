# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module OrganizationBanners
      # Renders the existing 75 / 90 / 100% admin budget-threshold banner
      # (produced by Billing::Notifications::CustomerBudgetsNotifications) on
      # broad organization and enterprise pages, so admins see budget pressure
      # in their normal workflow rather than only on /settings/billing.
      #
      # Polymorphic: pass `organization:` for org pages or `business:` for
      # enterprise pages (never both).
      class BudgetThresholdBannerComponent < ApplicationComponent
        include ApplicationComponent::Rescuable

        NUDGE_CATEGORY = T.let("general_ipm_budget_threshold_alert", String)
        FEATURE_FLAG = T.let(:general_ipm_budget_threshold_alert, Symbol)

        # The billing-platform read can fail / time out; never let it break the
        # surrounding org or enterprise page. Render nothing on any error.
        rescue_from StandardError, with: :nothing

        sig do
          params(
            organization: T.nilable(Organization),
            business: T.nilable(Business),
            user: T.nilable(User),
            location: String
          ).void
        end
        def initialize(organization: nil, business: nil, user: nil, location: "global")
          # Polymorphic on owner: exactly one of `organization:` or `business:`
          # must be provided. Fail fast on an ambiguous (both) or empty (neither)
          # call rather than silently ignoring an arg or raising later at render.
          if organization.nil? == business.nil?
            raise ArgumentError, "provide exactly one of `organization:` or `business:`"
          end

          @organization = T.let(organization, T.nilable(Organization))
          @business = T.let(business, T.nilable(Business))
          @user = T.let(user, T.nilable(User))
          @enterprise_mode = T.let(!business.nil?, T::Boolean)
          @location = T.let(location, String)
        end

        sig { returns(T::Boolean) }
        def render?
          return false if user.blank?
          return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise?
          return false unless T.must(user).feature_flag_enabled?(FEATURE_FLAG, default: false)
          return false unless billing_prerequisites_met?
          return false unless actor_can_manage_budgets?

          banner.present?
        end

        sig { returns(T.nilable(Billing::Notifications::CombinedBudgetThresholdBanner)) }
        memoize def banner
          Billing::Notifications::CustomerBudgetsNotifications
            .new(owner: owner, actor: T.must(user))
            .combined_budget_threshold_banner(actor: T.must(user))
        end

        # Renders the budget-threshold banner as a React island, reusing the
        # billing team's existing payload contract (`to_payload_hash`) rather
        # than hand-rolling the banner in ERB. Mirrors the sibling
        # `TbbSetupBudgetBannerComponent` convention (thin Ruby component ->
        # `render_react_partial`).
        sig { returns(T.nilable(String)) }
        def call
          return unless render?

          # Full-bleed banner: emitted with no outer margin. The surface that
          # renders this banner owns spacing via its full-bleed banner zone, so
          # multiple full-bleed banners stack flush under a single bottom margin.
          render_react_partial(name: "ipm-budget-threshold-banner", props: banner_props)
        end

        # Props handed to the `ipm-budget-threshold-banner` React partial. The
        # `banner` key is the billing team's existing payload contract so the
        # React side can reuse their budget-threshold banner rendering instead of
        # duplicating markup.
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def banner_props
          {
            banner: T.must(banner).to_payload_hash,
            ctaHref: cta_href,
            analytics: {
              category: NUDGE_CATEGORY,
              location: location,
              # Per the issue: track 75 / 90 / 100 as a property on the event,
              # not as separate categories.
              threshold: T.must(banner).highest_threshold,
              variant: T.must(banner).variant.to_s,
              visibleEvent: visible_analytics_event,
              dismissEvent: dismiss_analytics_event,
              clickEvent: click_analytics_event,
            },
          }
        end

        sig { returns(String) }
        def cta_href
          if enterprise_mode
            "/enterprises/#{T.must(business).slug}/billing/budgets"
          else
            "/organizations/#{T.must(organization).display_login}/settings/billing/budgets"
          end
        end

        private

        sig { returns(T.nilable(Organization)) }
        attr_reader :organization

        sig { returns(T.nilable(Business)) }
        attr_reader :business

        sig { returns(T.nilable(User)) }
        attr_reader :user

        sig { returns(T::Boolean) }
        attr_reader :enterprise_mode

        sig { returns(String) }
        attr_reader :location

        sig { returns(T.any(Organization, Business)) }
        def owner
          enterprise_mode ? T.must(business) : T.must(organization)
        end

        sig { returns(T::Boolean) }
        def billing_prerequisites_met?
          entity = owner
          # No billing customer means there are no budgets to report on, and
          # `CustomerBudgetsNotifications` would raise on `entity.customer.id`.
          # Bail out before touching the billing platform.
          return false if entity.customer.nil?

          entity.feature_flag_enabled?(:billing_user_level_budgets, default: false) &&
            entity.feature_flag_enabled?(:billing_user_level_budgets_manage, default: false)
        end

        sig { returns(T::Boolean) }
        def actor_can_manage_budgets?
          actor = T.must(user)
          if enterprise_mode
            biz = T.must(business)
            biz.owner?(actor) || biz.billing_manager?(actor)
          else
            org = T.must(organization)
            org.admin_ids.include?(actor.id) || org.billing_manager?(actor)
          end
        end

        sig { returns(String) }
        def visible_analytics_event
          analytics_event("visible")
        end

        sig { returns(String) }
        def dismiss_analytics_event
          analytics_event("dismiss")
        end

        sig { returns(String) }
        def click_analytics_event
          analytics_event("click")
        end

        sig { params(action: String).returns(String) }
        def analytics_event(action)
          JSON.generate({
            category: NUDGE_CATEGORY,
            action: action,
            label: analytics_label,
          })
        end

        sig { returns(String) }
        def analytics_label
          "location:#{location};threshold:#{T.must(banner).highest_threshold};variant:#{T.must(banner).variant}"
        end
      end
    end
  end
end
