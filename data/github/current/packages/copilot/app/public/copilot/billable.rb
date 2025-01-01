# typed: strict
# frozen_string_literal: true

module Copilot
  module Billable
    extend T::Helpers
    include GitHub::Memoizer


    abstract!

    sig { returns(T::Boolean) }
    def copilot_billable?
      return true if billable_object.feature_enabled?(:copilot_for_business_free)
      return true if GitHub.multi_tenant_enterprise?

      billable = billable_object

      # If there is no billable object, we cannot bill
      return false if billable.nil?
      result = billable.metered_services_billable?(commercial_restriction_feature_type: :copilot)

      GitHub.logger.info(
        "Checked metered_services_billable",
        "gh.copilot.metered_services_billable.billable_object" => billable.class.name,
        "gh.copilot.measured_services_billable.billable_id" =>  billable.id,
        "gh.copilot.metered_services_billable" => result[:billable],
        "gh.copilot.metered_services_billable.reason" => result[:reason],
      )

      result[:billable]
    end

    sig { returns(T.any(::User, ::Business)) }
    memoize def billable_object
      object = __getobj__

      billable = if object.is_a?(::Organization)
        if object.business.present?
          object.business
        else
          object
        end
      else
        object
      end

      T.must(billable)
    end

    sig { returns(T.any(::Organization, ::Business, ::Customer, NilClass)) }
    def customer_for
      billable = billable_object
      case billable
      when ::Business, ::User
        billable.customer_for(Customer::DEFAULT_PURPOSE)
      else
        T.absurd(billable)
      end
    end


    sig { params(organization_to_exclude_id: Integer, assigned_user_id: Integer).returns(T::Array[Copilot::Seat]) }
    def users_other_seats_for_this_billable_entity(organization_to_exclude_id, assigned_user_id)
      ## Figure out who we are charging and ensure that the assigned user
      ## is not in another entity in the customer, this will prevent double billing.
      if billable_object.is_a?(::Business)
        org_ids = billable_object.organizations.pluck(:id) - [organization_to_exclude_id]
        Copilot::Seat.where(assigned_user_id: assigned_user_id, organization_id: org_ids).order(created_at: :desc).to_a
      elsif billable_object.is_a?(::Organization)
        # Organizations are standalone
        []
      else
        # TODO: do we need to log anything here?
        []
      end
    end

    sig { abstract.returns(T.any(::Organization, ::Business)) }
    def __getobj__; end
  end
end
