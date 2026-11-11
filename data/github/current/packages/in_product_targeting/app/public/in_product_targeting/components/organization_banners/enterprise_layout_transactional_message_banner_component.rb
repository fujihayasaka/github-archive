# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module OrganizationBanners
      # Renders an IPM transactional message on the shared enterprise layout
      # (page-key `:enterprise_layout`). Wraps the same eligibility chain as the
      # controller helper but as a component so it works regardless of which
      # controller renders `app/views/businesses/_layout.html.erb`.
      class EnterpriseLayoutTransactionalMessageBannerComponent < ApplicationComponent
        include ApplicationComponent::Rescuable
        include InProductTargeting::TransactionalMessageConcern

        OUTER_FLAG = T.let(:ipm_global_transactional_message_enterprise, Symbol)

        rescue_from StandardError, with: :nothing

        sig do
          params(
            business: T.nilable(Business),
            user: T.nilable(User)
          ).void
        end
        def initialize(business:, user:)
          @business = T.let(business, T.nilable(Business))
          @user = T.let(user, T.nilable(User))
        end

        sig { returns(T.nilable(String)) }
        def call
          payload = banner_payload
          return if payload.nil?

          render_react_partial(name: "ipm-transactional-message-banner", props: { banner: payload })
        end

        sig { returns(T::Boolean) }
        def render?
          return false if @user.nil?
          return false unless @user.feature_flag_enabled?(OUTER_FLAG, default: false)

          !banner_payload.nil?
        end

        private

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        memoize def banner_payload
          T.let(compute_banner_payload, T.nilable(T::Hash[Symbol, T.untyped]))
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def compute_banner_payload
          user = @user
          return nil if user.nil?

          context = InProductTargeting::TransactionalMessageConcern::EligibilityContext.new(
            enterprise: @business,
          )
          transactional_message_payload(user, :enterprise_layout, helpers, context)
        end
      end
    end
  end
end
