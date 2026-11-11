# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module DashboardNudges
      # Renders the Digital-Front-Door (DFD) "new tasks" enterprise dashboard nudges
      # as React partials (BannerNudgeCard), migrated out of the ERB
      # BusinessNudgeComponent.
      #
      # We can render 0, 1, or 2 nudges per business:
      #  - the Copilot Business (CB) nudge
      #  - the highest-priority "Org Sequence" nudge (:org, :repo, :code, :ghas)
      #
      # Eligibility is UNCHANGED: it reuses DfdNudgeConcern's
      # `show_dfd_new_tasks_nudge?`, so the same users see the same nudges as before.
      # Only the presentation moves from ERB to React. Follows the
      # CopilotCliEnabledDashboardNudgeComponent precedent of a thin component that
      # builds props and calls `render_react_partial`.
      class DfdDashboardNudgesComponent < ApplicationComponent
        include ApplicationComponent::Rescuable
        include InProductTargeting::DfdNudgeConcern
        include InProductTargeting::EnterpriseNudgeConcern

        rescue_from StandardError, with: :nothing

        NudgeConfig = InProductTargeting::NudgeConcern::NudgeConfig

        NUDGE_LOCATION = T.let("dashboard", String)
        PARTIAL_NAME = T.let("banner-nudge-card", String)

        # Static, per-variant copy/icon/CTA ported verbatim from the ERB
        # BusinessNudgeComponent `case nudge_type` block. The `title` is dynamic
        # (uses the business profile name or oldest repo name) so it is computed in
        # `title_for`.
        VARIANTS = T.let(
          {
            cb: {
              category: "dfd_dashboard_enable_cb_nudge_1",
              description: "Copilot Business is available to your enterprise free for 30 days. Activate AI-powered coding for your team by verifying your identity.",
              icon_path: "modules/dashboard/promos/general/copilot-menu-no-indicator-1746823169.svg",
              cta_title: "Enable Copilot Business",
              cta_action: "activate_copilot_business",
            },
            org: {
              category: "dfd_dashboard_create_org_nudge_1",
              description: "The first step to seeing the benefits of GitHub Enterprise is to add its first organization, which will provide a home for your developers, code, and workflows.",
              icon_path: "modules/dashboard/promos/general/org-menu-no-indicator-1749137782.svg",
              cta_title: "Create organization",
              cta_action: "create_org",
            },
            repo: {
              category: "dfd_dashboard_create_repo_nudge_1",
              description: "Repositories are where you add code, collaborate, and utilize premium features, like GitHub Actions and Advanced Security.",
              icon_path: "modules/dashboard/promos/general/repo-menu-no-indicator-1749494944.svg",
              cta_title: "Create repository",
              cta_action: "create_repo",
            },
            code: {
              category: "dfd_dashboard_add_code_nudge_1",
              description: "Put GitHub Secret scanning, Code scanning, and Actions to work in your enterprise for the first time by adding code to your repo.",
              icon_path: "modules/dashboard/promos/general/code-menu-no-indicator-1752091508.svg",
              cta_title: "Add code",
              cta_action: "add_code",
            },
            ghas: {
              category: "dfd_dashboard_enable_ghas_nudge_1",
              description: "Protect your repository's code by enabling GitHub to scan for secrets and security issues.",
              icon_path: "modules/dashboard/promos/general/ghas-menu-no-indicator-1758667123.svg",
              cta_title: "Enable Advanced Security",
              cta_action: "enable_ghas",
            },
          }.freeze,
          T::Hash[Symbol, T::Hash[Symbol, String]]
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

          if @user.feature_flag_enabled?(:dfd_new_tasks, default: false)
            @nudges_to_render.push(get_dfd_new_tasks_config(:cb)) if show_dfd_new_tasks_nudge?(user, business, :cb)

            # ordered by priority
            org_sequence_nudges = [:org, :repo, :code, :ghas]
            org_sequence_nudge_to_show = org_sequence_nudges.find { |type| show_dfd_new_tasks_nudge?(user, business, type) }

            @nudges_to_render.push(get_dfd_new_tasks_config(org_sequence_nudge_to_show)) if org_sequence_nudge_to_show
          end
        end

        sig { returns(T.nilable(String)) }
        def call
          return unless render?

          safe_join(
            nudges_to_render.filter_map do |nudge|
              props = react_props_for(nudge)

              # Some nudges (e.g. `:code`/`:ghas`) build their title from a repo
              # name. If no associated repo is available the title would render as
              # "Add code to " / "Enable Advanced Security for ", so skip the nudge
              # entirely rather than surface a broken-looking card. This mirrors the
              # old ERB component, which errored and rendered nothing in that case.
              next if props[:title].blank?

              InProductTargeting::NudgeMemory.new(user).save_a_copy_of_impression_analytics_to_dotcom(id: nudge.nudge_id, group: nudge.nudge_group, enterprise_id: business.id)

              # `data-test-selector` is a non-production-only server-side hook (the
              # same one the ERB BusinessNudgeComponent emitted via `test_selector`)
              # so dashboard integration tests can locate a specific nudge by
              # category. `test_selector_data_hash` returns {} in production.
              # BannerNudgeCard applies the real test-selector/analytics DOM
              # attributes client-side, which integration tests can't observe.
              wrapper_options = { class: "tmp-mb-4", **test_selector_data_hash(props.dig(:analytics, :category)) }

              content_tag(:div, wrapper_options) do
                render_react_partial(name: PARTIAL_NAME, props: props)
              end
            end
          )
        end

        sig { returns(T::Boolean) }
        def render?
          return false unless user.subscribed_to_in_product_messages?
          return false if nudges_to_render.empty?
          return false if business.suspended?
          return false unless ::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", business_id: business.id)
          true
        end

        # Serializable props passed to the generic React `banner-nudge-card` partial,
        # one hash per nudge. Extracted so the copy/CTA/analytics shape can be unit
        # tested directly — `render_react_partial` emits nothing until the github-ui
        # bundle is in the manifest, so the rendered output can't be asserted pre-merge.
        sig { params(nudge: NudgeConfig).returns(T::Hash[Symbol, T.untyped]) }
        def react_props_for(nudge)
          variant = T.must(VARIANTS[nudge.nudge_type])
          category = variant.fetch(:category)

          {
            title: title_for(nudge.nudge_type),
            # Render as a standalone dashboard card (own border/padding, <h3> title)
            # rather than the default settings-row style.
            displayStyle: "dashboard",
            segments: [
              { type: "text", content: variant.fetch(:description) },
            ],
            iconPath: image_path(variant.fetch(:icon_path)),
            ctaTitle: variant.fetch(:cta_title),
            # DFD nudges use click-and-redirect (NOT dismiss-and-redirect).
            ctaHref: click_and_redirect_path(
              destination_key: nudge.destination_key,
              business_id: business.id,
              notice: nudge.nudge_id,
              group: nudge.nudge_group,
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
              ctaAction: variant.fetch(:cta_action),
              entityId: business.id,
            },
            testSelector: "enterprise-dashboard-#{business.id}-dfd-#{nudge.nudge_type}-nudge",
          }
        end

        sig { returns(T.nilable(Repository)) }
        def oldest_repo
          user_orgs = ::Organization
            .includes(business_membership: [:business])
            .where(business_organization_memberships: { business_id: business.id })

          user_orgs
            .map { |org| org.repositories_associated_with(user) }
            .flatten
            .sort_by(&:created_at)
            .first
        end

        private

        sig { params(nudge_type: Symbol).returns(String) }
        def title_for(nudge_type)
          case nudge_type
          when :cb
            "Copilot Business is available for #{business.safe_profile_name}"
          when :org
            "Create the first organization in #{business.safe_profile_name}"
          when :repo
            "Create the first repository in #{business.safe_profile_name}"
          when :code
            repo = oldest_repo
            repo ? "Add code to #{repo.name}" : ""
          when :ghas
            repo = oldest_repo
            repo ? "Enable Advanced Security for #{repo.name}" : ""
          else
            ""
          end
        end
      end
    end
  end
end
