# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Billing
      extend T::Helpers
      include Copilot::Businesses::Signatures

      abstract!

      sig { override.returns(T.nilable(String)) }
      def copilot_billing_type
        # This is a very hacky method but we gotta do it.
        # The billing type can come from the organization, from a customer associated with the organization, from the business (if enterprise linked) or from the business' customer (if enterprise linked)
        biz_billing_type          = business_object.billing_type # this is the organization's business' billing type
        biz_customer_billing_type = business_object.customer&.billing_type # this is the organization's business' customer's billing type

        billing_types = [
          biz_billing_type, # then look at this
          biz_customer_billing_type, # finally this
        ].compact.uniq

        tags = [
          "biz_billing_type:#{biz_billing_type}",
          "biz_customer_billing_type:#{biz_customer_billing_type}"
        ]

        # let's see if we have more than one billing types
        if billing_types.length > 1
          # we are just going to log this
          billing_types.each_with_index do |billing_type, index|
            tags << "billing_types_#{index}:#{billing_type}"
          end

          GitHub.logger.info(
            "copilot_billing_type: More than one billing type found",
            "gh.biz.billing_type" => biz_billing_type,
            "gh.biz.customer.billing_type" => biz_customer_billing_type,
          )
        end

        billing_type = billing_types.first
        GitHub.dogstats.increment(
          "copilot.billing_type.org_billing_type",
          tags: tags
        )
        billing_type
      end

      sig { override.returns(Integer) }
      def copilot_seat_count
        copilot_seats.count
      end

      sig { override.returns(T::Array[Copilot::Seat]) }
      def copilot_seats
        Copilot::Seat.for_business(business_object)
      end

      sig { override.returns(Integer) }
      def copilot_seat_assignment_count
        copilot_seat_assignments.count
      end

      sig { override.returns(T::Array[Copilot::SeatAssignment]) }
      def copilot_seat_assignments
        Copilot::SeatAssignment.for_business(business_object)
      end

      sig { abstract.returns(::Business) }
      def business_object; end
    end
  end
end
