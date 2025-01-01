# typed: strict
# frozen_string_literal: true

module Organization::FeatureFlagDependency
  extend T::Helpers

  include GitHub::FlipperActor
  include GitHub::VexiActor

  # Overwrite the feature_flag_actor_name in GitHub::VexiActor
  sig { override.returns(String) }
  def feature_flag_actor_name
    current_org = T.cast(self, Organization)
    current_org.display_login
  end

  # Provide a custom implementation of the from_feature_flag_actor_name class method to override the one in GitHub::VexiActor
  module ClassMethods
    sig { params(name: String).returns(T.nilable(GitHub::VexiActor)) }
    def from_feature_flag_actor_name(name)
      Organization.find_by_login name
    end
  end

  mixes_in_class_methods(ClassMethods)

  # Overwrite the actor_tenant in GitHub::VexiActor
  sig { override.returns(T.nilable(FeatureManagement::ActorTenant)) }
  def actor_tenant
    current_org = T.cast(self, Organization)
    if GitHub.multi_tenant_enterprise? && current_org.business
      tenant = T.must(current_org.business)
      FeatureManagement::ActorTenant.new(tenant.name, tenant.id)
    else
      nil
    end
  end
end
