# typed: strict
# frozen_string_literal: true

class Business
  module FeatureFlagMethods
    extend T::Helpers
    extend T::Sig

    include GitHub::FlipperActor
    include GitHub::VexiActor

    sig { returns(T::Boolean) }
    def billing_vnext_enabled?
      T.cast(self, Business)

      self.feature_enabled?(:billing_vnext)
    end

    # Public: Check if this Enterprise has opted into PATs v2
    #
    # Returns a Boolean.
    sig { returns(T::Boolean) }
    def patsv2_enabled?
      biz = T.cast(self, Business)

      biz.opted_in_programmatic_access_tokens?
    end

    sig { returns(T::Boolean) }
    def ghec_invoiced_business?
      biz = T.cast(self, Business)
      # they have to be an invoiced business
      return false unless biz.billing_type.present?
      return false unless biz.billing_type == "invoice"

      # they have to have purchased at lease one license
      return false unless biz.total_purchased_licenses.present?
      return false unless biz.total_purchased_licenses > 0

      # they cannot have an enterprise agreement that's active
      return true unless biz.enterprise_agreements.where(status: "active").count > 0 && biz.customer.present? && T.must(biz.customer).azure_subscription_id.nil?

      false
    end

    # Overwrite the flipper_actor_name in GitHub::FlipperActor
    sig { override.returns(String) }
    def flipper_actor_name
      biz = T.cast(self, Business)
      biz.slug
    end

    # Overwrite the flipper_actor_display_name in GitHub::FlipperActor
    sig { override.returns(T.nilable(String)) }
    def flipper_actor_display_name
      biz = T.cast(self, Business)
      biz.name
    end

    # Provide a custom implementation of the from_flipper_actor_name class method to override the one in GitHub::FlipperActor
    module ClassMethods
      extend T::Sig

      sig { params(name: String).returns(T.nilable(GitHub::FlipperActor)) }
      def from_flipper_actor_name(name)
        Business.find_by(slug: name)
      end
    end

    mixes_in_class_methods(ClassMethods)

    # Overwrite the actor_tenant in GitHub::FlipperActor
    sig { returns(T.nilable(FeatureManagement::ActorTenant)) }
    def actor_tenant
      biz = T.cast(self, Business)
      # In Proxima, a tenant will always exist. Tenants do not exist in Dotcom.
      if GitHub.multi_tenant_enterprise?
        FeatureManagement::ActorTenant.new(biz.name, biz.id)
      else
        nil
      end
    end
  end
end
