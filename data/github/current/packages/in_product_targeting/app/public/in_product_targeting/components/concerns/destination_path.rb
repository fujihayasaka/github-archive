# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Components
    module Concerns
      # Shared assembly for IPM redirect "destination" paths.
      #
      # Host components implement `destination_url_params` (the ordered,
      # surface-specific query params) and `destination_business` (the Business
      # whose slug should be appended, if any). This concern owns the endpoint
      # selection and the consistent `business_slug` suffix, so a param shared
      # across surfaces only needs to change in one place instead of in every
      # base component.
      module DestinationPath
        extend T::Helpers

        abstract!

        private

        sig { overridable.returns(T::Boolean) }
        def use_dismiss_and_redirect
          false
        end

        sig { returns(String) }
        def destination_path
          endpoint = use_dismiss_and_redirect ? "dismiss-and-redirect" : "click-and-redirect"
          params = destination_url_params
          biz_slug = destination_business&.slug
          params = params.merge(business_slug: biz_slug) if biz_slug
          query = params.map { |key, value| "#{key}=#{value}" }.join("&")
          "/in-product-messaging/#{endpoint}?#{query}"
        end

        # Ordered, surface-specific query params. `business_slug` is appended
        # separately by `destination_path` and must not be included here.
        sig { abstract.returns(T::Hash[Symbol, T.untyped]) }
        def destination_url_params; end

        # The Business whose slug should be appended to the path, if present.
        sig { abstract.returns(T.nilable(Business)) }
        def destination_business; end
      end
    end
  end
end
