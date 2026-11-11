# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module OrganizationBanners
      # Renders a Primer Banner nudging org admins / enterprise owners to set up
      # a per-user Copilot budget. Polymorphic: pass `organization:` for org pages
      # or `business:` for enterprise pages (never both).
      class TbbSetupBudgetBannerComponent < ApplicationComponent
        include ApplicationComponent::Rescuable

        NUDGE_ID = T.let(:general_ipm_tbb_setup_budget, Symbol)
        NUDGE_CATEGORY = T.let("general_ipm_tbb_setup_budget", String)
        FEATURE_FLAG = T.let(:general_ipm_tbb_setup_budget, Symbol)

        rescue_from StandardError, with: :nothing

        COPILOT_PRICING_TARGET_IDS = T.let(
          %w[copilot_premium_request premium_requests].freeze,
          T::Array[String]
        )

        sig do
          params(
            organization: T.nilable(Organization),
            business: T.nilable(Business),
            user: T.nilable(User),
            location: String
          ).void
        end
        def initialize(organization: nil, business: nil, user: nil, location: "org")
          @organization = T.let(organization, T.nilable(Organization))
          @business = T.let(business || organization&.business, T.nilable(Business))
          @user = T.let(user, T.nilable(User))
          @enterprise_mode = T.let(!business.nil? && organization.nil?, T::Boolean)
          @location = T.let(location, String)
        end

        sig { returns(T.nilable(String)) }
        def call
          return unless render?

          # Full-bleed banner: emitted with no outer margin. The surface that
          # renders this banner owns spacing via its full-bleed banner zone, so
          # multiple full-bleed banners stack flush under a single bottom margin.
          render_react_partial(name: "ipm-tbb-setup-budget-banner", props: {
            entityName: entity_name,
            ctaHref: cta_href,
            dismissPath: dismiss_path,
            analytics: {
              category: NUDGE_CATEGORY,
              visibleEvent: visible_analytics_event,
              dismissEvent: dismiss_analytics_event,
              clickEvent: click_analytics_event,
              location: location,
            },
          })
        end

        sig { returns(T::Boolean) }
        def render?
          return false if user.blank?
          return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise?
          return false if T.must(user).is_enterprise_managed?
          return false unless T.must(user).feature_flag_enabled?(FEATURE_FLAG, default: false)

          if enterprise_mode
            render_enterprise?
          else
            render_organization?
          end
        end

        sig { returns(String) }
        def cta_href
          if enterprise_mode || business.present?
            base_path = "/enterprises/#{T.must(business).slug}/billing/budgets/new"
            flag_target = T.must(business)
          else
            base_path = "/organizations/#{T.must(organization).display_login}/settings/billing/budgets/new"
            flag_target = T.must(organization)
          end

          if flag_target.feature_flag_enabled?(:ipm_budget_deep_linking, default: false)
            "#{base_path}?budget_type=premium_requests&budget_scope=multi_user_customer"
          else
            base_path
          end
        end

        sig { returns(String) }
        def dismiss_analytics_event
          JSON.generate({
            category: NUDGE_CATEGORY,
            action: "dismiss",
            label: analytics_label,
            **analytics_context,
          })
        end

        sig { returns(String) }
        def click_analytics_event
          JSON.generate({
            category: NUDGE_CATEGORY,
            action: "click",
            label: analytics_label,
            **analytics_context,
          })
        end

        sig { returns(String) }
        def visible_analytics_event
          JSON.generate({
            category: NUDGE_CATEGORY,
            action: "visible",
            label: analytics_label,
            **analytics_context,
          })
        end

        private

        sig { returns(T.nilable(Organization)) }
        attr_reader :organization

        sig { returns(T.nilable(User)) }
        attr_reader :user

        sig { returns(T.nilable(Business)) }
        attr_reader :business

        sig { returns(T::Boolean) }
        attr_reader :enterprise_mode

        sig { returns(String) }
        attr_reader :location

        sig { returns(String) }
        def entity_name
          if enterprise_mode
            T.must(business).name
          else
            T.must(organization).display_login
          end
        end

        sig { returns(String) }
        def dismiss_path
          params = { notice: NUDGE_ID.to_s, per_user: "true" }

          if enterprise_mode
            params[:business_id] = T.must(business).id.to_s
          else
            params[:organization_id] = T.must(organization).id.to_s
          end

          "/growth/notice_dismissals?#{params.to_query}"
        end

        sig { returns(String) }
        def analytics_label
          if enterprise_mode
            "location:enterprise;enterprise:#{T.must(business).slug}"
          else
            "location:org;organization:#{T.must(organization).display_login}"
          end
        end

        sig { returns(T::Hash[Symbol, T.untyped]) }
        def analytics_context
          ctx = T.let({}, T::Hash[Symbol, T.untyped])

          if enterprise_mode
            ctx[:enterprise] = T.must(business).id
          else
            org = T.must(organization)
            ctx[:organization] = org.id
            ctx[:plan] = org.plan.name
            ctx[:enterprise] = T.must(business).id if business.present?
          end

          ctx
        end

        sig { returns(T::Boolean) }
        def render_organization?
          org = T.must(organization)
          if business.present?
            return false unless T.must(business).owner?(T.must(user)) || T.must(business).billing_manager?(T.must(user))
          else
            return false unless org.admin_ids.include?(T.must(user).id) || org.billing_manager?(T.must(user))
          end
          return false if business.present? && is_business_in_active_dfd_trial?(T.must(business))
          return false if business.present? && T.must(business).trial_expired?
          return false unless billing_prerequisites_met?(org)
          return false if has_copilot_multi_user_budget?(org)
          return false if enterprise_already_has_copilot_budget?
          return false if dismissed?

          true
        end

        sig { returns(T::Boolean) }
        def render_enterprise?
          biz = T.must(business)
          return false unless biz.owner?(T.must(user)) || biz.billing_manager?(T.must(user))
          return false if is_business_in_active_dfd_trial?(biz)
          return false if biz.trial_expired?
          return false unless billing_prerequisites_met?(biz)
          return false if has_copilot_multi_user_budget?(biz)
          return false if dismissed?

          true
        end

        sig { returns(T::Boolean) }
        def dismissed?
          if enterprise_mode
            Growth::NoticeDismissal.new(T.must(user)).dismissed_business_notice?(
              NUDGE_ID.to_s,
              business_id: T.must(business).id
            )
          else
            Growth::NoticeDismissal.new(T.must(user)).dismissed_organization_notice?(
              NUDGE_ID.to_s,
              organization_id: T.must(organization).id
            )
          end
        end

        sig { params(entity: T.any(Organization, Business)).returns(T::Boolean) }
        def billing_prerequisites_met?(entity)
          entity.feature_flag_enabled?(:billing_user_level_budgets, default: false) &&
            entity.feature_flag_enabled?(:billing_user_level_budgets_manage, default: false)
        end

        sig { params(entity: T.any(Organization, Business)).returns(T::Boolean) }
        def has_copilot_multi_user_budget?(entity)
          Billing::MultiUserBudgetCheck.has_copilot_multi_user_budget?(entity)
        end

        sig { returns(T::Boolean) }
        def enterprise_already_has_copilot_budget?
          return false if business.blank?

          has_copilot_multi_user_budget?(T.must(business))
        end

        sig { params(biz: Business).returns(T::Boolean) }
        def is_business_in_active_dfd_trial?(biz)
          !!(
            biz.dfd_trial? &&
            biz.trial_expires_at &&
            biz.trial_expires_at >= Time.current &&
            biz.no_trial_or_active_trial?
          )
        end
      end
    end
  end
end
