# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module SettingsNudges
      # Renders eligible organization settings nudges as a single React partial
      # (`nudge-card-stack`, i.e. the `Stackable` component in github-ui), which
      # collapses additional cards behind a "Show more recommendations" toggle.
      #
      # Mirrors EnterpriseStackableNudgesComponent for the
      # /settings/organizations row. Eligibility is UNCHANGED: it reuses
      # OrganizationNudgeConcern's `show_organization_tasks_nudge?`, so the same
      # users see the same nudges as the existing ERB
      # OrganizationListItemNudgeComponent. Only the presentation moves from ERB
      # to a stacked React partial — every eligible nudge is rolled into a
      # single `cards:` array so the React Stackable can render the stack as one
      # tree.
      class OrganizationStackableNudgeComponent < ApplicationComponent
        include ApplicationComponent::Rescuable
        include InProductTargeting::OrganizationNudgeConcern

        rescue_from StandardError, with: :nothing

        NudgeConfig = InProductTargeting::NudgeConcern::NudgeConfig

        NUDGE_LOCATION = T.let("settings_organizations", String)
        PARTIAL_NAME = T.let("nudge-card-stack", String)

        # Order matches OrganizationListItemNudgeComponent#initialize — same
        # eligibility checks, same display order.
        NUDGE_KEYS = T.let(
          [
            :win_cb_users_back_credit_offer_to_accept,
            :win_cb_users_back_credit_assign_seats,
            :win_cb_users_back_credit,
            :raf_cb,
            :copilot_cli_enablement,
          ].freeze,
          T::Array[Symbol]
        )

        # Nudge variants whose CTA dismisses-then-redirects (rather than the
        # default click-and-redirect). Ported from the
        # `use_dismiss_and_redirect = true` branches of the ERB.
        DISMISS_AND_REDIRECT_KEYS = T.let(
          [:win_cb_users_back_credit_offer_to_accept].freeze,
          T::Array[Symbol]
        )

        # Winback variants that append an inline "Terms apply" link after the
        # description. Mirrors the `secondary_cta = link_to("Terms apply", ...)`
        # branches in the ERB OrganizationListItemNudgeComponent.
        WINBACK_TERMS_KEYS = T.let(
          [
            :win_cb_users_back_credit_offer_to_accept,
            :win_cb_users_back_credit,
            :win_cb_users_back_credit_assign_seats,
          ].freeze,
          T::Array[Symbol]
        )

        # href for the "Terms apply" secondary link. The ERB hard-codes "#"
        # with a TODO to replace it before the December 2025 winback flag is
        # enabled, so we keep the same placeholder here for strict parity.
        # Update both this constant and the ERB at the same time when the real
        # URL is known.
        TERMS_APPLY_HREF = T.let("#", String)

        # Static, per-variant copy/icon/CTA/analytics ported verbatim from the
        # ERB OrganizationListItemNudgeComponent `case nudge_type` block. Fields
        # that depend on runtime data (raf_cb member count, winback expiry
        # dates) are computed in `react_props_for`.
        ICON_PATH = T.let(
          "modules/dashboard/promos/general/copilot-menu-no-indicator-1746823169.svg",
          String
        )

        VARIANTS = T.let(
          {
            raf_cb: {
              category: "cb_settings_organizations_new_tasks_nudge_1",
              description: "Your members have requested access to Copilot. Review their requests and assign seats to offer them access.",
              cta_title: "Review access requests",
              cta_action: "review_access_requests",
            },
            win_cb_users_back_credit_offer_to_accept: {
              category: "digital_offer_nudge_cb_organizations_winback_to_accept_dec_2025_1",
              title: "$200 Copilot Business credit available",
              cta_title: "Apply credit",
              cta_action: "apply_credit",
            },
            win_cb_users_back_credit: {
              category: "digital_offer_nudge_cb_organizations_winback_approved_dec_2025_1",
              title: "Your $200 credit is ready",
              cta_title: "Enable Copilot Business",
              cta_action: "activate_copilot_business",
            },
            win_cb_users_back_credit_assign_seats: {
              category: "digital_offer_nudge_cb_organizations_winback_assign_seats_dec_2025_1",
              title: "Your $200 credit is ready",
              cta_title: "Assign seats",
              cta_action: "assign_seats",
            },
            copilot_cli_enablement: {
              category: "accelerate_ipm_settings_organizations_copilot_cli_nudge_1",
              title: "Enable Copilot CLI for your developers",
              description: "Give developers AI in the terminal using existing Copilot licenses. Inherits your organization's policies, guardrails, and governance settings.",
              cta_title: "Enable Copilot CLI",
              cta_action: "enable_copilot_cli",
            },
          }.freeze,
          T::Hash[Symbol, T::Hash[Symbol, String]]
        )

        sig { returns(T::Array[NudgeConfig]) }
        attr_reader :nudges_to_render

        sig { returns(User) }
        attr_reader :user

        sig { returns(::Organization) }
        attr_reader :organization

        sig { params(organization: ::Organization, user: User).void }
        def initialize(organization:, user:)
          @organization = T.let(organization, ::Organization)
          @user = T.let(user, User)

          @nudges_to_render = T.let([], T::Array[NudgeConfig])

          NUDGE_KEYS.each do |key|
            if show_organization_tasks_nudge?(user, organization, key)
              @nudges_to_render.push(get_new_tasks_nudge_config(key, organization))
            end
          end
        end

        sig { returns(T.nilable(String)) }
        def call
          return unless render?

          rendered_nudges = nudges_to_render
          cards = rendered_nudges.map do |nudge|
            InProductTargeting::NudgeMemory.new(user).save_a_copy_of_impression_analytics_to_dotcom(
              id: nudge.nudge_id, group: nudge.nudge_group, org_id: organization.id
            )
            react_props_for(nudge)
          end

          # `data-test-selector` is a non-production-only server-side hook (the
          # same one the ERB OrganizationListItemNudgeComponent emitted via
          # `test_selector`) so integration tests can locate the stack wrapper.
          # `test_selector_data_hash` returns {} in production. BannerNudgeCard
          # applies the per-card test-selector/analytics DOM attributes
          # client-side, which integration tests can't observe.
          wrapper_options = { class: "tmp-mx-3 tmp-mb-3", **test_selector_data_hash("organization-stackable-nudges-#{organization.id}") }

          content_tag(:div, wrapper_options) do
            # Per-card hidden markers so integration tests (which run
            # server-side and never execute the React partial) can find each
            # nudge by its analytics category, per-card test-selector, CTA
            # href, description text, dismiss form, and `data-analytics-*`
            # attributes — the same hooks the legacy
            # OrganizationListItemNudgeComponent emitted via `test_selector`,
            # `analytics_visible_attributes`, `analytics_click_attributes`,
            # and the `<a class="ipm-nudge-cta" ...>` link.
            # `build_test_markers` no-ops in production so these elements
            # never ship to users; BannerNudgeCard renders the visible
            # card/CTA/dismiss control client-side.
            safe_join([
              build_test_markers(rendered_nudges, cards),
              render_react_partial(name: PARTIAL_NAME, props: { cards: cards }),
            ])
          end
        end

        # Builds the per-card hidden test markers. Extracted so the render
        # path is easy to skip in production. See `call` for the rationale.
        # Production users see only the React-rendered BannerNudgeCard; the
        # hidden server-side markers exist purely for integration tests that
        # never execute the React partial. Emitting them in production would
        # double-count analytics with the React card, so we short-circuit.
        sig do
          params(
            nudges: T::Array[NudgeConfig],
            cards: T::Array[T::Hash[Symbol, T.untyped]],
          ).returns(ActiveSupport::SafeBuffer)
        end
        private def build_test_markers(nudges, cards)
          return ActiveSupport::SafeBuffer.new if Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

          safe_join(
            nudges.zip(cards).flat_map do |nudge, card|
              card = T.must(card)
              analytics = T.cast(card[:analytics], T::Hash[Symbol, T.untyped])
              category = analytics[:category].to_s
              group = analytics[:group]
              plan = analytics[:plan]
              entity_id = analytics[:entityId]
              cta_action = analytics[:ctaAction]
              visible_context = { organization: entity_id, plan: plan, group: group }
              parts = T.let([], T::Array[String])

              parts << content_tag(
                :span,
                "",
                data: analytics_visible_attributes(category: category, **visible_context),
                **test_selector_data_hash(category),
              )

              parts << content_tag(
                :a,
                card[:ctaTitle],
                {
                  class: "ipm-nudge-cta d-none",
                  href: card[:ctaHref],
                  data: analytics_click_attributes(
                    category: category,
                    tag: "a",
                    action: cta_action,
                    organization: entity_id,
                    plan: plan,
                    location: NUDGE_LOCATION,
                    group: group,
                  ),
                  **test_selector_data_hash(card[:testSelector]),
                },
              )

              parts << content_tag(
                :div,
                safe_join([
                  content_tag(:h3, card[:title].to_s),
                  content_tag(
                    :p,
                    safe_join(
                      Array(card[:segments]).map { |seg| seg[:content].to_s },
                      " ",
                    ),
                  ),
                ]),
                class: "ipm-nudge-content d-none",
              )

              if should_show_dismiss_button?(nudge) && card[:dismissPath].present?
                parts << content_tag(
                  :form,
                  "",
                  action: card[:dismissPath],
                  method: "post",
                  class: "d-none",
                  data: analytics_click_attributes(
                    category: category,
                    action: "dismiss",
                    organization: entity_id,
                    plan: plan,
                    location: NUDGE_LOCATION,
                    group: group,
                  ),
                  **test_selector_data_hash("settings-organizations-#{entity_id}-#{nudge.nudge_type}-dismiss"),
                )
              end

              parts
            end
          )
        end

        sig { returns(T::Boolean) }
        def render?
          return false if user.nil?
          return false if nudges_to_render.empty?
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
          category = variant.fetch(:category)

          {
            title: title_for(nudge, variant),
            displayStyle: "dashboard",
            segments: segments_for(nudge, variant),
            iconPath: image_path(ICON_PATH),
            ctaTitle: variant.fetch(:cta_title),
            ctaHref: cta_href_for(nudge),
            # `dismissPath: nil` suppresses the dismiss control client-side
            # (same pattern as CopilotWelcomeModalComponent). Mirrors the ERB
            # `should_show_dismiss_button?` guard: the raf_cb nudge hides its
            # dismiss button once the org has Copilot Business enabled so
            # admins can't permanently hide pending seat-request notifications.
            dismissPath: dismiss_path_for(nudge),
            analytics: {
              category: category,
              location: NUDGE_LOCATION,
              group: nudge.nudge_group,
              ctaAction: variant.fetch(:cta_action),
              entityId: organization.id,
              # `plan` is forwarded so Hydro consumers can slice nudge events
              # by org plan (free / team / enterprise). Mirrors the
              # `plan: organization.plan.name` argument the ERB passed to
              # `analytics_visible_attributes` and `analytics_click_attributes`.
              plan: organization.plan.name,
            },
            testSelector: "settings-organizations-#{organization.id}-#{nudge.nudge_type}-nudge",
          }
        end

        private

        sig { params(nudge: NudgeConfig, variant: T::Hash[Symbol, String]).returns(String) }
        def title_for(nudge, variant)
          return variant.fetch(:title) unless nudge.nudge_type == :raf_cb

          count = MemberFeatureRequest.total_for_feature(organization, MemberFeatureRequest::Feature::CopilotForBusiness)
          verb = count == 1 ? "user is" : "users are"
          "#{count} #{verb} waiting for access to Copilot."
        end

        # Builds the `segments` array passed to BannerNudgeCard. Winback
        # variants append an inline `link` segment for "Terms apply", mirroring
        # the `secondary_cta = link_to("Terms apply", "#", ...)` branches in
        # the ERB. Every other variant emits a single `text` segment so the
        # existing copy renders unchanged.
        sig do
          params(nudge: NudgeConfig, variant: T::Hash[Symbol, String]).returns(T::Array[T::Hash[Symbol, String]])
        end
        def segments_for(nudge, variant)
          segments = T.let(
            [{ type: "text", content: description_for(nudge, variant) }],
            T::Array[T::Hash[Symbol, String]]
          )
          if WINBACK_TERMS_KEYS.include?(nudge.nudge_type)
            segments << { type: "link", content: "Terms apply", href: TERMS_APPLY_HREF }
          end
          segments
        end

        sig { params(nudge: NudgeConfig, variant: T::Hash[Symbol, String]).returns(String) }
        def description_for(nudge, variant)
          case nudge.nudge_type
          when :win_cb_users_back_credit_offer_to_accept
            expires_display = nudge.formatted_expires_date || "Dec\u202f13, 2025"
            "Your org can apply a $200 credit toward Copilot Business. Offer expires #{expires_display}."
          when :win_cb_users_back_credit, :win_cb_users_back_credit_assign_seats
            expires_display = nudge.formatted_expires_date || "Dec\u202f13, 2025"
            expires_next_day_display = nudge.formatted_expires_next_day || "Dec 14"
            "Credits cover Copilot Business seat costs through #{expires_display}. Costs incurred over the credit amount or from #{expires_next_day_display} onward will be billed."
          else
            variant.fetch(:description)
          end
        end

        # Mirrors `OrganizationListItemNudgeComponent#should_show_dismiss_button?`:
        # the raf_cb nudge stops offering a dismiss button once the org has
        # Copilot Business enabled, because the "request access" requests it
        # surfaces still need admin attention (assigning seats) and we don't
        # want a one-click way to permanently hide them.
        sig { params(nudge: NudgeConfig).returns(T::Boolean) }
        def should_show_dismiss_button?(nudge)
          return false if nudge.nudge_type == :raf_cb && ::Copilot::Organization.new(organization).has_copilot_for_business?
          true
        end

        # Returns `nil` when `should_show_dismiss_button?` is false so the
        # React BannerNudgeCard suppresses the dismiss control (same nil-means-
        # hidden pattern as CopilotWelcomeModalComponent).
        sig { params(nudge: NudgeConfig).returns(T.nilable(String)) }
        def dismiss_path_for(nudge)
          return nil unless should_show_dismiss_button?(nudge)

          organization_dismiss_notice_path(
            notice: nudge.nudge_id,
            organization_id: organization.id,
            group: nudge.nudge_group,
          )
        end

        sig { params(nudge: NudgeConfig).returns(String) }
        def cta_href_for(nudge)
          params = {
            destination_key: nudge.destination_key,
            organization_id: organization.id,
            notice: nudge.nudge_id,
            group: nudge.nudge_group,
          }

          if DISMISS_AND_REDIRECT_KEYS.include?(nudge.nudge_type)
            dismiss_and_redirect_path(**params)
          else
            click_and_redirect_path(**params)
          end
        end
      end
    end
  end
end
