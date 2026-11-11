# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module OrganizationBanners
      # Base component for IPM banners on organization pages.
      # Subclasses must implement:
      # - eligible_for_banner?
      # - nudge_category, nudge_id, nudge_group
      # - banner_label, banner_title, banner_description
      # - primary_cta_text, primary_cta_href, primary_cta_action
      # - secondary_cta_text, secondary_cta_action (optional - for remind me later)
      # - dismiss_path
      # - banner_image_alt
      class OrganizationIpmBannerBaseComponent < ApplicationComponent
        extend T::Helpers

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
        end

        private

        sig { returns(T::Boolean) }
        def render?
          return false unless user.present?

          eligible_for_banner?
        end

        sig { returns(Organization) }
        attr_reader :organization

        sig { returns(T.nilable(User)) }
        attr_reader :user

        # Abstract methods that subclasses must implement
        sig { abstract.returns(T::Boolean) }
        def eligible_for_banner?; end

        sig { abstract.returns(String) }
        def nudge_category; end

        sig { abstract.returns(Symbol) }
        def nudge_id; end

        sig { abstract.returns(Symbol) }
        def nudge_group; end

        sig { abstract.returns(String) }
        def banner_label; end

        sig { abstract.returns(String) }
        def banner_title; end

        sig { abstract.returns(String) }
        def banner_description; end

        sig { abstract.returns(String) }
        def primary_cta_text; end

        sig { abstract.returns(String) }
        def primary_cta_href; end

        sig { abstract.returns(String) }
        def primary_cta_action; end

        sig { abstract.returns(String) }
        def dismiss_path; end

        sig { abstract.returns(String) }
        def banner_image_path_dark; end

        sig { abstract.returns(String) }
        def banner_image_path_light; end

        sig { abstract.returns(String) }
        def banner_image_alt_dark; end

        sig { abstract.returns(String) }
        def banner_image_alt_light; end

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
        def secondary_cta_action
          "remind_later"
        end

        sig { returns(String) }
        def dismiss_action
          "dismiss"
        end

        # Helper for tracking nudge impressions
        sig { void }
        def track_impression
          T.must(user).track_nudge_impression(id: nudge_id, group: nudge_group)
        end
      end
    end
  end
end
