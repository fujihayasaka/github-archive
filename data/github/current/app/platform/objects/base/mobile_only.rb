# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Base < GraphQL::Schema::Object
      # This adds semi-private features to the Public GraphQL API.
      #
      # When a type or field has `mobile_only true`, then it's only visible when:
      # - The oauth app is one of the possible mobile applictions
      module MobileOnly
        def mobile_only(mobile_only = nil)
          if mobile_only
            @mobile_only = mobile_only
          else
            @mobile_only
          end
        end

        if Rails.env.test?
          # This is only used for testing
          def mobile_only=(mobile_only)
            @mobile_only = mobile_only
          end
        end

        def generate_input_type
          apply_mobile_only_to_class(super)
        end

        def generate_payload_type
          apply_mobile_only_to_class(super)
        end

        private

        def apply_mobile_only_to_class(defn_class)
          if @mobile_only
            defn_class.mobile_only(@mobile_only)
          end
          defn_class
        end
      end
    end
  end
end
