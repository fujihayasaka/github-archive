# typed: strict
# frozen_string_literal: true

module InProductTargeting
  module Controllers
    module Concerns
      module UtmParams
        extend ActiveSupport::Concern
        extend T::Helpers

        abstract!

        sig { abstract.returns(T.nilable(User)) }
        def current_user; end

        # Adds utm_source and utm_medium parameters to a URL if they're not already present
        sig { params(url: String).returns(String) }
        def add_utm_params(url)
          user = current_user
          return url unless user&.feature_flag_enabled?(:in_product_messaging_auto_utms, default: false)

          uri = URI.parse(url)
          query_params = URI.decode_www_form(uri.query || "").to_h

          # Only add utm_source if not already present
          query_params["utm_source"] ||= "github"
          # Only add utm_medium if not already present
          query_params["utm_medium"] ||= "in_product_message"

          uri.query = URI.encode_www_form(query_params)

          # Handle fragment (anchor) - it should come after query params
          if uri.fragment
            "#{uri.to_s.sub(/#.*/, "")}##{uri.fragment}"
          else
            uri.to_s
          end
        end
      end
    end
  end
end
