# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module GlobalBanners
      # Renders the Copilot budget exhausted request banner globally for org members
      # whose Copilot usage budget has been fully consumed (100% threshold).
      #
      # This component reads budget data exclusively from GitHub::RemoteCache
      # (Global Cache / replicated Redis), populated by the
      # BudgetThresholdNotificationProcessor stream processor when a budget hits
      # 100%. One additional KV read (Growth::KV, reading replica) checks whether
      # the user has dismissed the banner for the current state and org.
      class CopilotBudgetRequestBannerComponent < ApplicationComponent
        include ApplicationComponent::Rescuable

        NUDGE_ID = T.let("copilot_budget_request_cta", String)
        NUDGE_CATEGORY = T.let("copilot_budget_request_cta", String)

        COPILOT_PRICING_TARGET_IDS = T.let(
          %w[copilot_enterprise copilot_premium_request premium_requests].freeze,
          T::Array[String]
        )

        DEFAULT_REQUESTED_AMOUNT_CENTS = T.let(10_000, Integer) # $100 USD

        rescue_from StandardError, with: :nothing

        sig { params(user: T.nilable(User)).void }
        def initialize(user:)
          @user = T.let(user, T.nilable(User))
          @cached_budget_data = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
          @cached_request_state = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        end

        # Delete the budget-exhausted cache entry for a user for a specific org.
        # If org_id is nil, invalidates the entire cache for the user.
        sig { params(user_id: Integer, org_id: T.nilable(Integer)).void }
        def self.clear_budget_cache_for_user(user_id, org_id: nil)
          client = Copilot::Cache::BudgetExhaustedClient.new(user_id: user_id)
          if org_id
            client.remove_entry(org_id)
          else
            client.invalidate
          end
        rescue StandardError
          # best-effort; cache will expire naturally via TTL
        end

        sig { returns(T.nilable(String)) }
        def call
          return unless render?

          content_tag(:div, class: "tmp-mb-4") do
            render_react_partial(name: "copilot-budget-request-banner", props: {
              isPersonalBudget: cached_personal_budget?,
              organizationName: cached_org_login,
              resetDate: cached_reset_date,
              requestUrl: request_url,
              requestedAmountCents: DEFAULT_REQUESTED_AMOUNT_CENTS,
              removeRequestUrl: remove_request_url,
              contactUrl: contact_url,
              dismissPaths: dismiss_paths,
              bannerState: banner_state,
              declinedDate: declined_date,
              analytics: {
                visibleEvent: visible_analytics_event,
                dismissEvent: dismiss_analytics_event,
                clickEvent: click_analytics_event,
                location: "global",
              },
            })
          end
        end

        sig { returns(T::Boolean) }
        def render?
          return false if user.blank?
          return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise?
          return false unless FeatureFlag.vexi.enabled?(:copilot_budget_request_cta, T.must(user), default: false)

          load_cached_budget_data!
          return false if @cached_budget_data.nil?

          load_cached_request_state!
          return false if dismissed_for_current_state?

          true
        end

        private

        sig { returns(T.nilable(User)) }
        attr_reader :user

        sig { void }
        def load_cached_budget_data!
          client = Copilot::Cache::BudgetExhaustedClient.new(user_id: T.must(user).id)
          entries = client.fetch_entries
          return if entries.empty?

          # Pick the first entry (most recently exhausted budgets are appended last,
          # but any entry is valid for display).
          @cached_budget_data = entries.first
        end

        sig { void }
        def load_cached_request_state!
          org_id = T.must(@cached_budget_data)["org_id"]
          client = Copilot::Cache::BudgetRequestStateClient.new(user_id: T.must(user).id, org_id: org_id)
          raw = client.fetch { nil }
          return if raw.nil?

          @cached_request_state = raw
        end

        # Checks whether the user has dismissed the banner for the current state
        # and org. Uses Growth::KV (a single KV read from the reading replica).
        sig { returns(T::Boolean) }
        def dismissed_for_current_state?
          Growth::NoticeDismissal.new(T.must(user)).dismissed_organization_notice?(
            notice_id_for_state(banner_state),
            organization_id: cached_org_id,
          )
        rescue StandardError
          # If KV is unavailable, allow rendering (fail-open)
          false
        end

        sig { returns(String) }
        def cached_org_login
          T.must(@cached_budget_data)["org_login"]
        end

        sig { returns(Integer) }
        def cached_org_id
          T.must(@cached_budget_data)["org_id"]
        end

        sig { returns(String) }
        def cached_reset_date
          T.must(@cached_budget_data).fetch("reset_date", "next billing cycle")
        end

        sig { returns(T::Boolean) }
        def cached_personal_budget?
          !!T.must(@cached_budget_data)["personal_budget"]
        end

        sig { returns(String) }
        def banner_state
          return "pre_request" if @cached_request_state.nil?
          @cached_request_state.fetch("state", "pre_request")
        end

        sig { returns(T.nilable(String)) }
        def declined_date
          return nil if @cached_request_state.nil?
          @cached_request_state["declined_date"]
        end

        sig { returns(String) }
        def request_url
          "/orgs/#{cached_org_login}/copilot/budget_request"
        end

        sig { returns(String) }
        def remove_request_url
          "/orgs/#{cached_org_login}/copilot/budget_request"
        end

        sig { returns(String) }
        def contact_url
          "/orgs/#{cached_org_login}/people#org-members-admin"
        end

        sig { params(state: String).returns(String) }
        def notice_id_for_state(state)
          "#{NUDGE_ID}_#{state}"
        end

        sig { returns(T::Hash[String, String]) }
        def dismiss_paths
          %w[pre_request post_request request_denied].each_with_object({}) do |state, hash|
            params = {
              notice: notice_id_for_state(state),
              per_user: "true",
              organization_id: cached_org_id.to_s,
            }
            hash[state] = "/growth/notice_dismissals?#{params.to_query}"
          end
        end

        sig { returns(String) }
        def visible_analytics_event
          JSON.generate({
            category: NUDGE_CATEGORY,
            action: "visible",
            label: analytics_label,
          })
        end

        sig { returns(String) }
        def dismiss_analytics_event
          JSON.generate({
            category: NUDGE_CATEGORY,
            action: "dismiss",
            label: analytics_label,
          })
        end

        sig { returns(String) }
        def click_analytics_event
          JSON.generate({
            category: NUDGE_CATEGORY,
            action: "click",
            label: analytics_label,
          })
        end

        sig { returns(String) }
        def analytics_label
          "location:global;organization:#{cached_org_login}"
        end
      end
    end
  end
end
