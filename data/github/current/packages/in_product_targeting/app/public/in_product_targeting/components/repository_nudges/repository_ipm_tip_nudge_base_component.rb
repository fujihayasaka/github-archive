# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module RepositoryNudges
      # Base component for IPM tip nudges on the repository page.
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
      class RepositoryIpmTipNudgeBaseComponent < ApplicationComponent
        extend T::Helpers

        NUDGE_LOCATION = "repository"
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

        sig { void }
        def call
          if render?
            content_tag(:div) do
              render_react_partial(name: "ipm-tip-notification", props: {
                title: nudge_title,
                hotspot: hotspot,
                body: nudge_description,
                link: { label: nudge_cta, href: nudge_cta_href },
                group: NUDGE_GROUP,
                location: NUDGE_LOCATION,
                category: nudge_category,
                action: nudge_cta_action,
                userId: current_user.id,
                isFloating: true,
                hasIntro: true
              })
            end
          end
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
        def feature_flag_name; end

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
        def hotspot; end

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
          return false unless current_user.feature_flag_enabled?(feature_flag_name, default: false)
          return false unless current_user.subscribed_to_in_product_messages?
          return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise? || current_user.is_enterprise_managed?
          return false unless repository.owner.is_a?(Organization)
          return false if current_user.dismissed_organization_notice?(nudge_id.to_s, organization)
          return false unless repository.adminable_by?(current_user)

          true
        end
      end
    end
  end
end
