# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module TransactionalMessageBannerHelper
    include InProductTargeting::TransactionalMessageConcern

    # Build props for the in-product-targeting React partial.
    # Returns nil if there is no message to show.
    sig do
      params(
        user: User,
        page: Symbol,
        organization: T.nilable(Organization),
        enterprise: T.nilable(Business)
      ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
    end
    def transactional_message_banner_props(user, page, organization: nil, enterprise: nil)
      context = InProductTargeting::TransactionalMessageConcern::EligibilityContext.new(
        organization: organization,
        enterprise: enterprise,
      )
      payload = transactional_message_payload(user, page, self, context)
      return nil unless payload

      { banner: payload }
    end
  end
end
