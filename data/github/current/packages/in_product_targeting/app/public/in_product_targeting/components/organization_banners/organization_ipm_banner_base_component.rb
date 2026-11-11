# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module OrganizationBanners
      # Base component for IPM banners on organization pages.
      # Subclasses must implement:
      # - eligible_for_nudge?
      # - nudge_category, nudge_id, nudge_group
      # - nudge_title, nudge_description
      # - primary_cta_text, primary_cta_href, primary_cta_action
      # - secondary_cta_text, secondary_cta_action (optional - for remind me later)
      # - dismiss_path
      # - nudge_image_alt
      class OrganizationIpmBannerBaseComponent < ApplicationComponent
        extend T::Helpers
        include InProductTargeting::Components::Concerns::DestinationPath

        NUDGE_LOCATION = "org_overview"

        abstract!

        sig do
          params(
            organization: Organization,
            user: T.nilable(User)
          ).void
        end
        def initialize(organization:, user:)
          @organization = T.let(organization, Organization)
          @user = T.let(user, T.nilable(User))
          @business = T.let(organization.business, T.nilable(Business))
          @plan = T.let(organization.plan, T.nilable(GitHub::Plan))
        end

        sig { returns(T.nilable(String)) }
        def call
          if render?
            InProductTargeting::NudgeMemory.new(current_user).save_a_copy_of_impression_analytics_to_dotcom(id: nudge_id, group: nudge_group)
            content_tag(:div, class: "tmp-mb-4") do
              props = {
                heading: nudge_title,
                description: nudge_description,
                primaryActionText: primary_cta_text,
                primaryActionHref: primary_cta_href || destination_path,
                secondaryActionText: show_secondary_cta? ? secondary_cta_text : nil,
                secondaryActionHref: show_secondary_cta? && secondary_cta_href.present? ? secondary_cta_href : nil,
                secondaryActionPostPath: show_secondary_cta? && secondary_cta_post_path.present? ? secondary_cta_post_path : nil,
                secondaryActionPostBehavior: show_secondary_cta? && secondary_cta_post_path.present? ? secondary_cta_post_behavior : nil,
                productShotDark: nudge_image_path_dark,
                productShotLight: nudge_image_path_light,
                productShotAltText: nudge_image_alt_dark,
                showProductShotBackground: true,
                dismissible: true,
                dismissPath: dismiss_path,
                label: nudge_label,
                analytics: {
                    group: nudge_group,
                    location: NUDGE_LOCATION,
                    category: nudge_category,
                    primaryCtaAction: primary_cta_action,
                    secondaryCtaAction: show_secondary_cta? ? secondary_cta_action : nil,
                    dismissAction: dismiss_action,
                    userId: current_user&.id,
                    organizationId: organization.id,
                    enterpriseId: business&.id,
                }.merge(additional_analytics),
              }

              flash = show_secondary_cta? ? secondary_action_flash : nil
              props[:secondaryActionFlash] = flash if flash.present?

              render_react_partial(name: "upsell-banner", props: props)
            end
          end
        end

        private

        sig { returns(T::Boolean) }
        def render?
          return false unless user.present?
          return false unless common_eligibility_checks_pass?
          return false unless subscribed_to_in_product_messages?
          eligible_for_nudge?
        end

        sig { returns(Organization) }
        attr_reader :organization

        sig { returns(T.nilable(User)) }
        attr_reader :user

        sig { returns(T.nilable(Business)) }
        attr_reader :business

        sig { returns(T.nilable(GitHub::Plan)) }
        attr_reader :plan

        # Abstract methods that subclasses must implement
        sig { abstract.returns(T::Boolean) }
        def eligible_for_nudge?; end

        sig { abstract.returns(Symbol) }
        def feature_flag; end

        sig { abstract.returns(String) }
        def nudge_category; end

        sig { abstract.returns(Symbol) }
        def nudge_id; end

        sig { abstract.returns(Symbol) }
        def nudge_group; end

        # Returns nil or a label options hash for the banner label, such as `{:text => "..."}`
        # with an optional `:variant` key for the color scheme.
        # See Primer Label docs https://primer.style/product/components/label/
        sig { overridable.returns(T.nilable(T::Hash[Symbol, String])) }
        def nudge_label
          nil
        end

        sig { abstract.returns(String) }
        def nudge_title; end

        sig { abstract.returns(String) }
        def nudge_description; end

        sig { abstract.returns(String) }
        def primary_cta_text; end

        sig { overridable.returns(T.nilable(String)) }
        def primary_cta_href
          nil
        end

        sig { abstract.returns(String) }
        def primary_cta_action; end

        sig { abstract.returns(String) }
        def dismiss_path; end

        sig { abstract.returns(String) }
        def nudge_image_path_dark; end

        sig { abstract.returns(String) }
        def nudge_image_path_light; end

        sig { abstract.returns(String) }
        def nudge_image_alt_dark; end

        sig { abstract.returns(String) }
        def nudge_image_alt_light; end

        # Optional methods with defaults - subclasses can override
        sig { returns(T::Boolean) }
        def show_secondary_cta?
          false
        end

        sig { returns(String) }
        def secondary_cta_text
          "Remind me later"
        end

        sig { returns(String) }
        def secondary_cta_href
          ""
        end

        sig { returns(String) }
        def secondary_cta_post_path
          ""
        end

        sig { returns(String) }
        def secondary_cta_post_behavior
          "click"
        end

        sig { returns(String) }
        def secondary_cta_action
          "remind_later"
        end

        # Optional ephemeral confirmation flash shown client-side after the secondary
        # CTA is clicked. Returns nil unless a subclass opts in. When present, the
        # `upsell-banner` React partial replaces the banner in place with an info
        # banner. This is pure frontend state - no notice, no dismissal, no endpoint.
        sig { overridable.returns(T.nilable(T::Hash[Symbol, String])) }
        def secondary_action_flash
          nil
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
          business
        end

        sig { returns(String) }
        def dismiss_action
          "dismiss"
        end

        # Additonal analytics to be tracked outside of the base set
        sig { returns(T::Hash[Symbol, T.untyped]) }
        def additional_analytics
          {}
        end

        # Helper for tracking nudge impressions
        sig { void }
        def track_impression
          InProductTargeting::NudgeMemory.new(T.must(user)).save_a_copy_of_impression_analytics_to_dotcom(id: nudge_id, group: nudge_group)
        end

        sig { returns(T::Boolean) }
        def subscribed_to_in_product_messages?
          return false unless ::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", organization_id: organization.id)
          return false if business && !::InProductTargeting.domain.messaging_subscribed?(field: "promotion_subscribed", business_id: business&.id)

          true
        end

        sig { returns(T::Boolean) }
        def common_eligibility_checks_pass?
          return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise? || T.must(user).is_enterprise_managed?
          return false unless T.must(user).feature_flag_enabled?(feature_flag, default: false)

          true
        end
      end
    end
  end
end
