# typed: true
# frozen_string_literal: true

module Settings
  class InProductMessagingComponent < ApplicationComponent
    OwnerType = T.type_alias { T.any(::Organization, ::Business) }

    sig { params(owner: OwnerType).void }
    def initialize(owner:)
      @owner = owner
    end

    private

    sig { returns(OwnerType) }
    attr_reader :owner

    sig { returns(String) }
    def heading
      "In-product messages"
    end

    sig { returns(String) }
    def entity_name
      owner.is_a?(::Organization) ? "organization" : "enterprise"
    end

    sig { params(field: String).returns(String) }
    def toggle_path(field)
      o = owner
      if o.is_a?(::Organization)
        organization_in_product_messaging_path(o, field:)
      else
        settings_in_product_messaging_enterprise_path(o, field:)
      end
    end

    sig { params(field: String).returns(T::Boolean) }
    def checked?(field)
      o = owner
      if o.is_a?(::Organization)
        ::InProductTargeting.domain.messaging_subscribed?(organization_id: o.id, field:)
      else
        ::InProductTargeting.domain.messaging_subscribed?(business_id: o.id, field:)
      end
    end

    sig { returns(T::Boolean) }
    def show_members_request?
      o = owner
      flag = o.is_a?(::Organization) ? :in_product_messaging_organization_members_request : :in_product_messaging_business_members_request
      o.feature_flag_enabled?(flag, default: false)
    end
  end
end
