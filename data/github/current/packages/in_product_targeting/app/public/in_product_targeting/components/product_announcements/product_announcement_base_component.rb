# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module ProductAnnouncements
      # Abstract base for product announcement components that encapsulate
      # eligibility logic and display metadata for in-product announcements.
      # Subclasses can be rendered as ViewComponents (via `call`) or used as
      # data providers (via `props`) for controllers that build their own payloads.
      # Subclasses must implement:
      # - eligible?
      # - label
      # - dismiss_path
      # - nudge_id
      # - feature_flag_name
      class ProductAnnouncementBaseComponent < ApplicationComponent
        extend T::Helpers

        abstract!

        sig { params(user: User).void }
        def initialize(user:)
          @user = T.let(user, User)
        end

        sig { abstract.returns(T::Boolean) }
        def eligible?; end

        sig { abstract.returns(String) }
        def label; end

        sig { abstract.returns(String) }
        def dismiss_path; end

        sig { abstract.returns(Symbol) }
        def nudge_id; end

        sig { abstract.returns(String) }
        def nudge_category; end

        sig { abstract.returns(String) }
        def feature_flag_name; end

        # Common eligibility checks shared across subclasses
        sig { returns(T::Boolean) }
        def base_eligibility_checks_are_satisfied?
          return false if GitHub.multi_tenant_enterprise? || GitHub.enterprise?
          return false unless user.feature_flag_enabled?(feature_flag_name, default: false)
          return false if user.dismissed_notice?(nudge_id.to_s)

          true
        end

        private

        sig { returns(User) }
        attr_reader :user
      end
    end
  end
end
