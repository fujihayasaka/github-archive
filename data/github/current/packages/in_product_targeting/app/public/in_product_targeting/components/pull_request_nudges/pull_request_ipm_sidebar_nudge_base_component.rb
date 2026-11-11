# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module PullRequestNudges
      # Base component for IPM nudges on the PR sidebar.
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
      class PullRequestIpmSidebarNudgeBaseComponent < ApplicationComponent
        extend T::Helpers

        NUDGE_LOCATION = "pull_request"
        NUDGE_GROUP = :engage

        abstract!

        sig do
          params(
            repository: Repository
          ).void
        end
        def initialize(repository:)
          @repository = T.let(repository, Repository)
        end

        private

        sig { returns(T::Boolean) }
        def render?
          !!(logged_in? && eligible_for_nudge?)
        end

        sig { returns(Repository) }
        attr_reader :repository

        sig { abstract.returns(T::Boolean) }
        def eligible_for_nudge?; end

        sig { abstract.returns(String) }
        def nudge_cta_href; end

        # Abstract methods for nudge configuration - subclasses must override
        sig { abstract.returns(String) }
        def nudge_category; end

        sig { abstract.returns(Symbol) }
        def nudge_id; end

        # Abstract methods for nudge content - subclasses must override
        sig { abstract.returns(String) }
        def nudge_title; end

        sig { abstract.returns(String) }
        def nudge_description; end

        sig { abstract.returns(String) }
        def nudge_cta; end

        sig { abstract.returns(String) }
        def nudge_cta_action; end

        sig { abstract.returns(String) }
        def nudge_image_path_dark; end

        sig { abstract.returns(String) }
        def nudge_image_path_light; end

        sig { abstract.returns(String) }
        def nudge_image_alt_dark; end

        sig { abstract.returns(String) }
        def nudge_image_alt_light; end

        sig { overridable.returns(String) }
        def nudge_dismiss_form_path
          organization_dismiss_notice_path(
            notice: nudge_id,
            organization_id: organization.id,
            group: NUDGE_GROUP
          )
        end

        sig { returns(Organization) }
        memoize def organization
          T.cast(repository.owner, Organization)
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
          return false unless repository.owner.is_a?(Organization)
          return false if current_user.dismissed_organization_notice?(nudge_id.to_s, organization)

          true
        end
      end
    end
  end
end
