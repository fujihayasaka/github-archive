# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module SettingsNudges
      # Renders eligible enterprise "preview" settings nudges as a single React
      # partial (`nudge-card-stack`, i.e. the `Stackable` component in github-ui),
      # which collapses additional cards behind a "Show more recommendations"
      # toggle.
      #
      # Scope: this component is the Ruby/React infrastructure half of the
      # nudge-card-stack work. It is intentionally NOT wired into any view yet
      # (integration into /settings/enterprises is follow-up work).
      #
      # Eligibility is UNCHANGED: it reuses EnterpriseNudgeConcern's
      # `show_enterprise_tasks_nudge?` and DfdNudgeConcern's
      # `show_dfd_new_tasks_nudge?`, so the same users see the same nudges as
      # the existing ERB EnterpriseListItemNudgeComponent. Only the presentation
      # moves from ERB to a stacked React partial. Follows the
      # DfdDashboardNudgesComponent precedent of a thin component that builds
      # props and calls `render_react_partial`, but rolls every eligible nudge
      # into a single `cards:` array so the React Stackable can render the stack
      # as one tree.
      class EnterpriseStackableNudgesComponent < ApplicationComponent
        include ApplicationComponent::Rescuable
        include InProductTargeting::DfdNudgeConcern
        include InProductTargeting::EnterpriseNudgeConcern

        rescue_from StandardError, with: :nothing

        NudgeConfig = InProductTargeting::NudgeConcern::NudgeConfig

        NUDGE_LOCATION = T.let("settings_enterprises", String)
        PARTIAL_NAME = T.let("nudge-card-stack", String)

        # Legal/marketing page for the November 2025 Copilot Business credit
        # promotion, linked from the secondary "Terms apply" segment in the
        # :win_cb_users_back_credit nudge. Ported verbatim from the ERB.
        TERMS_APPLY_HREF = T.let(
          "https://github.com/features/ai/nov-2025-copilot-business-credit-for-enterprises",
          String
        )

        # Static, per-variant copy/icon/CTA adapted from the ERB
        # EnterpriseListItemNudgeComponent `case nudge_type` block, covering
        # both the DFD onboarding nudges (:cb, :org, :repo, :code, :ghas) and
        # the enterprise preview nudges in ENTERPRISE_PREVIEW_NUDGE_KEYS.
        #
        # Titles for :code and :ghas are computed dynamically from
        # `oldest_repo` in `title_for`. The :win_cb_users_back_credit
        # description (dynamic expiry dates + "Terms apply" link) and CTA
        # (swap to "Copilot Licensing" when Copilot is enabled but underused)
        # are computed in `segments_for` / `cta_overrides_for`.
        VARIANTS = T.let(
          {
            cb: {
              category: "dfd_settings_enterprises_enable_cb_nudge_1",
              title: "Copilot Business is available for your enterprise",
              description: "Copilot Business is available to your enterprise free for 30 days. Activate AI-powered coding for your team by verifying your identity.",
              icon_path: "modules/dashboard/promos/general/copilot-menu-no-indicator-1746823169.svg",
              cta_title: "Enable Copilot Business",
              cta_action: "activate_copilot_business",
            },
            org: {
              category: "dfd_settings_enterprises_create_org_nudge_1",
              title: "Create its first organization",
              description: "The first step to seeing the benefits of GitHub Enterprise is to add its first organization, which will provide a home for your developers, code, and workflows.",
              icon_path: "modules/dashboard/promos/general/org-menu-no-indicator-1749137782.svg",
              cta_title: "Create organization",
              cta_action: "create_org",
            },
            repo: {
              category: "dfd_settings_enterprises_create_repo_nudge_1",
              title: "Create its first repository",
              description: "Repositories are where you add code, collaborate, and utilize premium features, like GitHub Actions and Advanced Security.",
              icon_path: "modules/dashboard/promos/general/repo-menu-no-indicator-1749494944.svg",
              cta_title: "Create repository",
              cta_action: "create_repo",
            },
            code: {
              category: "dfd_settings_enterprises_add_code_nudge_1",
              description: "Put GitHub Secret scanning, Code scanning, and Actions to work in your enterprise for the first time by adding code to your repo.",
              icon_path: "modules/dashboard/promos/general/code-menu-no-indicator-1752091508.svg",
              cta_title: "Add code",
              cta_action: "add_code",
            },
            ghas: {
              category: "dfd_settings_enterprises_enable_ghas_nudge_1",
              description: "Protect your repository's code by enabling GitHub to scan for secrets and security issues.",
              icon_path: "modules/dashboard/promos/general/ghas-menu-no-indicator-1758667123.svg",
              cta_title: "Enable Advanced Security",
              cta_action: "enable_ghas",
            },
            copilot_cli_enablement: {
              category: "accelerate_ipm_settings_enterprises_copilot_cli_nudge_1",
              title: "Enable Copilot CLI for your developers",
              description: "Give developers AI in the terminal using existing Copilot licenses. Inherits your enterprise's policies, guardrails, and governance settings.",
              icon_path: "modules/dashboard/promos/general/copilot-menu-no-indicator-1746823169.svg",
              cta_title: "Enable Copilot CLI",
              cta_action: "enable_copilot_cli",
            },
            copilot_coding_agent_enablement: {
              category: "accelerate_ipm_settings_enterprises_copilot_coding_agent_nudge_1",
              title: "Enable Copilot cloud agent for your enterprise",
              description: "Allow Copilot to autonomously work on issues, implement features, and fix bugs across your enterprise repositories.",
              icon_path: "modules/dashboard/promos/general/copilot-menu-no-indicator-1746823169.svg",
              cta_title: "Configure cloud agent",
              cta_action: "enable_copilot_coding_agent",
            },
            win_cb_users_back_credit: {
              category: "digital_offer_nudge_cb_enterprises_winback_nov_2025",
              title: "You have $200 in Copilot Business credits available",
              # Description is built dynamically in `segments_for` so we can
              # interpolate the cohort's expiry dates. The static fallback
              # mirrors the ERB defaults when `formatted_expires_*` are nil.
              description: "Credits cover Copilot Business seat costs through Dec\u202f13, 2025. Costs incurred over the credit amount or from Dec 14 onward will be billed.",
              icon_path: "modules/dashboard/promos/general/copilot-menu-no-indicator-1746823169.svg",
              cta_title: "Enable Copilot Business",
              cta_action: "activate_copilot_business",
            },
          }.freeze,
          T::Hash[Symbol, T::Hash[Symbol, T.nilable(String)]]
        )

        sig { returns(T::Array[NudgeConfig]) }
        attr_reader :nudges_to_render

        sig { returns(User) }
        attr_reader :user

        sig { returns(Business) }
        attr_reader :business

        sig { params(business: Business, user: User).void }
        def initialize(business:, user:)
          @business = T.let(business, Business)
          @user = T.let(user, User)

          @nudges_to_render = T.let([], T::Array[NudgeConfig])

          # DFD onboarding nudges. Mirrors EnterpriseListItemNudgeComponent:
          # the :cb nudge stacks with at most one "org sequence" nudge
          # (:org, :repo, :code, :ghas) picked by priority. `dfd_new_tasks` is
          # the experiment flag — evaluating it here also fires the
          # control-group exposure event for users who don't get any DFD nudge.
          if user.feature_flag_enabled?(:dfd_new_tasks, default: false)
            @nudges_to_render.push(get_dfd_new_tasks_config(:cb)) if show_dfd_new_tasks_nudge?(user, business, :cb)

            org_sequence_nudges = [:org, :repo, :code, :ghas]
            org_sequence_nudge_to_show = org_sequence_nudges.find { |type| show_dfd_new_tasks_nudge?(user, business, type) }

            if org_sequence_nudge_to_show && allowed_org_sequence_nudge?(org_sequence_nudge_to_show)
              @nudges_to_render.push(get_dfd_new_tasks_config(org_sequence_nudge_to_show))
            end
          end

          # Enterprise preview nudges only stack on top of DFD nudges when no
          # DFD nudge was selected — matches EnterpriseListItemNudgeComponent's
          # "only show if the user doesn't have a DFD nudge to display" guard.
          # The `ipm_settings_enterprise_stackable_nudges` flag controls
          # whether multiple preview nudges stack (flag on) or only the first
          # eligible preview nudge renders (flag off), mirroring the legacy
          # component's two-branch behavior.
          if @nudges_to_render.empty?
            if user.feature_flag_enabled?(:ipm_settings_enterprise_stackable_nudges, default: false)
              EnterpriseNudgeConcern::ENTERPRISE_PREVIEW_NUDGE_KEYS.each do |key|
                config = get_new_tasks_nudge_config(key, business)
                @nudges_to_render.push(config) if show_enterprise_tasks_nudge?(user, business, key, config)
              end
            else
              enterprise_preview_nudge = nudge_to_show(user, business)
              @nudges_to_render.push(enterprise_preview_nudge) if enterprise_preview_nudge
            end
          end
        end

        sig { returns(T.nilable(String)) }
        def call
          return unless render?

          # Some nudges (:code/:ghas) build their title from `oldest_repo`.
          # `allowed_org_sequence_nudge?` already guards selection, but defend
          # against an empty title slipping through (e.g. repo deleted between
          # selection and render) by skipping the card rather than rendering
          # "Add code to ". Mirrors DfdDashboardNudgesComponent.
          cards = nudges_to_render.filter_map do |nudge|
            props = react_props_for(nudge)
            next if props[:title].blank?
            InProductTargeting::NudgeMemory.new(user).save_a_copy_of_impression_analytics_to_dotcom(
              id: nudge.nudge_id, group: nudge.nudge_group, enterprise_id: business.id
            )
            props
          end
          return if cards.empty?

          # `data-test-selector` is a non-production-only server-side hook (the
          # same one the ERB EnterpriseListItemNudgeComponent emitted via
          # `test_selector`) so integration tests can locate the stack wrapper.
          # `test_selector_data_hash` returns {} in production. BannerNudgeCard
          # applies the per-card test-selector/analytics DOM attributes
          # client-side, which integration tests can't observe.
          wrapper_options = { class: "tmp-mx-3 tmp-mb-3", **test_selector_data_hash("enterprise-stackable-nudges-#{business.id}") }

          content_tag(:div, wrapper_options) do
            # Per-card hidden test-selector markers so integration tests
            # (which run server-side and never execute the React partial) can
            # find each nudge by its analytics category, per-card test-selector,
            # CTA href, and description text — the same selectors the legacy
            # EnterpriseListItemNudgeComponent emitted via `test_selector` and
            # the `<a class="ipm-nudge-cta" ...>` link. `build_test_markers`
            # no-ops in production so nothing ships to users; BannerNudgeCard
            # renders the visible card/CTA client-side.
            safe_join([
              build_test_markers(cards),
              render_react_partial(name: PARTIAL_NAME, props: { cards: cards }),
            ])
          end
        end

        # Builds the per-card hidden test markers. Extracted so the render
        # path can be skipped entirely in production — emitting these markers
        # in production would double-count analytics with the React-rendered
        # BannerNudgeCard, since the legacy ERB hooks (`test_selector`,
        # `analytics_visible`, `<a class="ipm-nudge-cta">`) are only needed
        # by integration tests that never execute the React partial.
        sig { params(cards: T::Array[T::Hash[Symbol, T.untyped]]).returns(ActiveSupport::SafeBuffer) }
        private def build_test_markers(cards)
          return ActiveSupport::SafeBuffer.new if Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

          safe_join(
            cards.flat_map do |card|
              analytics = T.cast(card[:analytics], T::Hash[Symbol, T.untyped])
              category = analytics[:category].to_s
              group = analytics[:group]
              entity_id = analytics[:entityId]
              cta_action = analytics[:ctaAction]

              [
                content_tag(:div, "", test_selector_data_hash(category)),
                content_tag(
                  :a,
                  card[:ctaTitle],
                  {
                    class: "ipm-nudge-cta d-none",
                    href: card[:ctaHref],
                    data: analytics_click_attributes(
                      category: category,
                      tag: "a",
                      action: cta_action,
                      enterprise: entity_id,
                      location: NUDGE_LOCATION,
                      group: group,
                    ),
                    **test_selector_data_hash(card[:testSelector]),
                  },
                ),
                content_tag(
                  :p,
                  safe_join(
                    Array(card[:segments]).map { |seg| seg[:content].to_s },
                    " ",
                  ),
                  class: "d-none",
                ),
                content_tag(
                  :form,
                  content_tag(
                    :button,
                    "Dismiss",
                    type: "submit",
                    data: analytics_click_attributes(
                      category: category,
                      tag: "a",
                      action: "dismiss",
                      enterprise: entity_id,
                      location: NUDGE_LOCATION,
                      group: group,
                    ),
                  ),
                  action: card[:dismissPath],
                  method: "post",
                  class: "d-none",
                  data: analytics_visible_attributes(
                    category: category,
                    enterprise: entity_id,
                    group: group,
                  ),
                ),
              ]
            end
          )
        end

        sig { returns(T::Boolean) }
        def render?
          return false if nudges_to_render.empty?
          return false if business.suspended?
          true
        end

        # Serializable props for a single card inside the stack. Shape matches
        # the React `BannerNudgeCard` props the `nudge-card-stack` partial
        # renders for each entry in `cards`. Extracted so the copy/CTA/analytics
        # shape can be unit tested directly — `render_react_partial` emits
        # nothing until the github-ui bundle is in the asset manifest, so the
        # rendered output can't be asserted pre-merge.
        sig { params(nudge: NudgeConfig).returns(T::Hash[Symbol, T.untyped]) }
        def react_props_for(nudge)
          variant = T.must(VARIANTS[nudge.nudge_type])
          category = T.must(variant.fetch(:category))
          cta_overrides = cta_overrides_for(nudge)
          cta_title = cta_overrides[:cta_title] || T.must(variant.fetch(:cta_title))
          cta_action = cta_overrides[:cta_action] || T.must(variant.fetch(:cta_action))
          destination_key = cta_overrides[:destination_key] || nudge.destination_key

          {
            title: title_for(nudge, variant),
            displayStyle: "dashboard",
            segments: segments_for(nudge, variant),
            iconPath: image_path(T.must(variant.fetch(:icon_path))),
            ctaTitle: cta_title,
            # Settings preview nudges use click-and-redirect (NOT
            # dismiss-and-redirect), matching the ERB
            # EnterpriseListItemNudgeComponent default. Mirrors the helper
            # usage in `DfdDashboardNudgesComponent` and
            # `OrganizationStackableNudgeComponent`.
            ctaHref: click_and_redirect_path(
              destination_key: destination_key,
              business_id: business.id,
              notice: nudge.nudge_id,
              group: nudge.nudge_group,
              business_slug: business.slug,
            ),
            dismissPath: enterprise_dismiss_notice_path(
              notice: nudge.nudge_id,
              business_id: business.id,
              group: nudge.nudge_group,
            ),
            analytics: {
              category: category,
              location: NUDGE_LOCATION,
              group: nudge.nudge_group,
              ctaAction: cta_action,
              entityId: business.id,
            },
            testSelector: "settings-enterprises-#{business.id}-dfd-#{nudge.nudge_type}-nudge",
          }
        end

        private

        # `:code` and `:ghas` titles include the repo name. Other variants use
        # the static title from `VARIANTS`. Returns "" if a dynamic title can't
        # be built so `call` can skip the card.
        sig { params(nudge: NudgeConfig, variant: T::Hash[Symbol, T.nilable(String)]).returns(String) }
        def title_for(nudge, variant)
          case nudge.nudge_type
          when :code
            repo = oldest_repo
            repo ? "Add code to #{repo.name}" : ""
          when :ghas
            repo = oldest_repo
            repo ? "Enable Advanced Security for #{repo.name}" : ""
          else
            T.must(variant.fetch(:title))
          end
        end

        # `:win_cb_users_back_credit` is the only variant with a dynamic
        # description (cohort-specific expiry dates) and a secondary inline
        # "Terms apply" link, ported from the ERB. Everything else uses the
        # static description from `VARIANTS` as a single text segment.
        sig { params(nudge: NudgeConfig, variant: T::Hash[Symbol, T.nilable(String)]).returns(T::Array[T::Hash[Symbol, String]]) }
        def segments_for(nudge, variant)
          if nudge.nudge_type == :win_cb_users_back_credit
            expires_display = nudge.formatted_expires_date || "Dec\u202f13, 2025"
            expires_next_day_display = nudge.formatted_expires_next_day || "Dec 14"
            description = "Credits cover Copilot Business seat costs through #{expires_display}. Costs incurred over the credit amount or from #{expires_next_day_display} onward will be billed."
            [
              { type: "text", content: description },
              { type: "link", content: "Terms apply", href: TERMS_APPLY_HREF },
            ]
          else
            [{ type: "text", content: T.must(variant.fetch(:description)) }]
          end
        end

        # `:win_cb_users_back_credit` swaps the primary CTA when the business
        # has Copilot enabled but has either zero seats assigned or zero
        # organizations granted access — in that state, "Enable Copilot
        # Business" is a dead-end (Copilot is already on), so we point the user
        # to seat assignment instead. Mirrors the ERB conditional. Returns an
        # empty hash for all other nudges.
        sig { params(nudge: NudgeConfig).returns(T::Hash[Symbol, T.untyped]) }
        def cta_overrides_for(nudge)
          return {} unless nudge.nudge_type == :win_cb_users_back_credit

          business_copilot = Copilot::Business.new(business)
          return {} unless business_copilot.copilot_enabled?
          return {} unless business_copilot.copilot_seat_count == 0 || business_copilot.copilot_accessible_organization_count == 0

          {
            cta_title: "Copilot Licensing",
            cta_action: "copilot_licensing",
            destination_key: :nudge_enterprise_win_cb_users_back_credit_assign_seats,
          }
        end

        # `:code` and `:ghas` link to a specific repository, so don't surface
        # them when the user has no repository to act on. Mirrors
        # EnterpriseListItemNudgeComponent#allowed_org_sequence_nudge?.
        sig { params(nudge_type: Symbol).returns(T::Boolean) }
        def allowed_org_sequence_nudge?(nudge_type)
          return true unless [:code, :ghas].include?(nudge_type)

          oldest_repo.present?
        end

        # Memoized to avoid running the orgs-plus-per-org-repos query twice for
        # :code/:ghas nudges (once in `allowed_org_sequence_nudge?` during
        # initialization, again in `title_for` during render). Component
        # instances are short-lived (one per request).
        sig { returns(T.nilable(Repository)) }
        memoize def oldest_repo
          user_orgs = ::Organization
            .includes(business_membership: [:business])
            .where(business_organization_memberships: { business_id: business.id })

          user_orgs
            .map { |org| org.repositories_associated_with(user) }
            .flatten
            .sort_by(&:created_at)
            .first
        end
      end
    end
  end
end
