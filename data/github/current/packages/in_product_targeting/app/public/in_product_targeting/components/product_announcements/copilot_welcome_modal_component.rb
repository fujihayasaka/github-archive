# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module ProductAnnouncements
      class CopilotWelcomeModalComponent < ProductAnnouncementBaseComponent
        include ApplicationComponent::Rescuable

        # Fail closed on the render (dashboard) path: if anything raises during the
        # `render_in` lifecycle, render nothing rather than break the host page.
        #
        # NOTE: this only covers `render_in` (i.e. `call`). It does NOT protect
        # callers that invoke `props` directly outside rendering, such as the
        # immersive payload (`Copilot::ImmersiveController#app_payload`).
        rescue_from StandardError, with: :nothing

        NUDGE_ID = :accelerate_ipm_copilot_business_onboarding_modal
        FEATURE_FLAG = "accelerate_ipm_copilot_business_onboarding_modal"
        NUDGE_CATEGORY = :accelerate_ipm_copilot_business_onboarding_modal
        NUDGE_GROUP = :engage

        sig { returns(T.nilable(String)) }
        def call
          return unless eligible?

          render_react_partial(name: "product-announcement", props: v2_props)
        end

        # Returns announcement payload for controllers that build their own
        # response (e.g. JSON payloads) without rendering the component, such as the
        # immersive SPA payload (`Copilot::ImmersiveController#app_payload`). Emits the
        # generic `product-announcement` shape under `copilotWelcomeModalV2` when the
        # modal is eligible, and nothing otherwise.
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def props
          return {} unless eligible?

          { copilotWelcomeModalV2: v2_props }
        end

        # Props for the generic `product-announcement` partial / SPA component: the
        # bundled `ccaOnboarding` data, the dismissal endpoint, and the analytics
        # `category`/`label`.
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def v2_props
          {
            announcementId: "ccaOnboarding",
            label: label,
            analytics: {
              category: nudge_category,
              label: analytics_label,
            },
            dismissPath: dismiss_path,
            shouldShowMainCta: true,
            shouldShowTabCtas: true,
          }
        end

        sig { override.returns(Symbol) }
        def nudge_id
          NUDGE_ID
        end

        sig { override.returns(String) }
        def nudge_category
          NUDGE_CATEGORY.to_s
        end

        sig { override.returns(String) }
        def feature_flag_name
          FEATURE_FLAG
        end

        sig { override.returns(T::Boolean) }
        memoize def eligible?
          return false unless base_eligibility_checks_are_satisfied?
          return false unless copilot_user.has_enterprise_seat? && copilot_user.copilot_seats.where("copilot_seats.created_at >= ?", 7.days.ago).exists?

          true
        end

        sig { override.returns(String) }
        def label
          case copilot_user.copilot_plan_from_cache
          when "enterprise" then "Copilot Enterprise"
          when "business" then "Copilot Business"
          else ""
          end
        end

        sig { override.returns(String) }
        def dismiss_path
          "/track-nudge-dismissal?id=#{NUDGE_ID}&group=#{NUDGE_GROUP}"
        end

        private

        # Click/visible analytics label for the welcome modal product announcement.
        sig { returns(String) }
        def analytics_label
          "nudge_id:#{nudge_id};nudge_category:#{nudge_category};user:#{user.display_login};plan:#{label};"
        end

        sig { returns(Copilot::Public::User) }
        memoize def copilot_user
          Copilot::Public::User.for(user)
        end
      end
    end
  end
end
