# typed: strict
# frozen_string_literal: true

module Organization::FeatureFlagDependency
  extend T::Helpers

  include GitHub::FlipperActor
  include GitHub::VexiActor

  # Overwrite the flipper_actor_name in GitHub::FlipperActor
  sig { override.returns(String) }
  def flipper_actor_name
    current_org = T.cast(self, Organization)
    current_org.display_login
  end

  # Overwrite the flipper_actor_display_name in GitHub::FlipperActor
  sig { override.returns(T.nilable(String)) }
  def flipper_actor_display_name
    current_org = T.cast(self, Organization)
    current_org.profile_name
  end

  # Provide a custom implementation of the from_flipper_actor_name class method to override the one in GitHub::FlipperActor
  module ClassMethods
    sig { params(name: String).returns(T.nilable(GitHub::FlipperActor)) }
    def from_flipper_actor_name(name)
      Organization.find_by_login name
    end
  end

  mixes_in_class_methods(ClassMethods)

  # Overwrite the actor_tenant in GitHub::FlipperActor
  sig { returns(T.nilable(FeatureManagement::ActorTenant)) }
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
