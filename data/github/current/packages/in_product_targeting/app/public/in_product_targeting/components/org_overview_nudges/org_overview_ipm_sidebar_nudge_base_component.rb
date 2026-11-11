# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module OrgOverviewNudges
      # Base component for IPM nudges on the Org Overview.
      # Subclasses must define:
      # - NUDGE_CATEGORY, NUDGE_ID constants
      # And implement:
      # - eligible_for_nudge?
      # - nudge_cta_href
      # - nudge_category, nudge_id
      # - nudge_title, nudge_description
      # - nudge_cta, nudge_cta_action
      # - nudge_image_path_dark, nudge_image_path_light
      # - nudge_image_alt_dark, nudge_image_alt_light
      class OrgOverviewIpmSidebarNudgeBaseComponent < ApplicationComponent
        extend T::Helpers

        NUDGE_LOCATION = "org_overview"
        NUDGE_GROUP = :engage

        abstract!

        sig do
          params(
            organization: Organization
          ).void
        end
        def initialize(organization:)
          @organization = T.let(organization, Organization)
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

        sig { abstract.returns(String) }
        def nudge_cta_href
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
          return false if current_user.dismissed_organization_notice?(nudge_id.to_s, organization)

          true
        end
      end
    end
  end
end
