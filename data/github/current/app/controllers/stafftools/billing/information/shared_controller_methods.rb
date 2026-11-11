# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    module Information
      module SharedControllerMethods
        extend ActiveSupport::Concern
        extend T::Helpers

        requires_ancestor { StafftoolsController }
        abstract!

        SHOW_PARAMS = T.let(%w[show_billing_info show_shipping_info].freeze, T::Array[String])

        sig { void }
        def create
          # Handle visibility toggle for billing and shipping info
          # Start with URL query params, then apply POST body params
          url_params = Rack::Utils.parse_nested_query(request.query_string)
          post_params = request.POST

          # Collect all show params that should be "true"
          new_params = {}
          SHOW_PARAMS.each do |param|
            # If it's in POST body, use that value; otherwise check URL params
            if post_params.key?(param)
              new_params[param] = "true" if post_params[param] == "true"
            elsif url_params[param] == "true"
              new_params[param] = "true"
            end
          end

          redirect_to_information_path(new_params)
        end

        private

        # Subclasses must implement this method to redirect to the correct path
        sig { abstract.params(params: T::Hash[String, String]).void }
        def redirect_to_information_path(params); end
      end
    end
  end
end
