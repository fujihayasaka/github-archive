# typed: true
# frozen_string_literal: true

module Notifications
  module TenantContext

    REPOSITORY_ID_METHOD = ->(obj) { obj.respond_to?(:repository_id) }
    REPOSITORY_METHOD = ->(obj) { obj.respond_to?(:repository) }
    RESOLVE_TENANT_METHOD = ->(obj) { obj.respond_to?(:resolve_tenant) }
    OWNER_METHOD = ->(obj) { obj.respond_to?(:owner) }

    module InspectorTrait
      extend T::Helpers
      interface!

      sig do
        abstract
          .params(tenant: T.nilable(Business), tags: T::Hash[String, T.untyped])
          .void
      end
      def log(tenant, tags = {}); end
    end

    class Inspector
      include InspectorTrait

      sig do
        override
          .params(tenant: T.nilable(Business), tags: T::Hash[String, T.untyped])
          .void
      end
      def log(tenant, tags = {})
        tags = tags.transform_keys { |key| "gh.notifications.#{key}" }
        GitHub.logger.info("Tenant resolution for Notifications", {
          "code.namespace" => "Notifications::TenantContext",
          "gh.notifications.tenant_resolved" => tenant ? true : false,
          "gh.notifications.tenant_id" => tenant ? tenant.id : nil,
        }.merge(tags))
      end
    end

    # Resolve the tenant associated to a Notifications' List (i.e: Repository)
    sig { params(list_type: String, list_id: Integer, inspector: InspectorTrait).returns(T.nilable(Business)) }
    def self.resolve_tenant_for_list(list_type:, list_id:, inspector: Inspector.new)
      resolve_tenant(list_type.constantize.find_by(id: list_id), inspector: inspector)
    rescue NameError
      inspector.log(nil, { "source_type" => list_type, "resolve_path" => "NameError" })
      nil
    end

    # Given an object, try to resolve its Tenant.
    # Notifications work with many kind of objects and each one can resolve
    # the tenant in a different way. This method tries to cover the
    # most common use cases
    sig { params(object: T.untyped, inspector: InspectorTrait).returns(T.nilable(Business)) }
    def self.resolve_tenant(object, inspector: Inspector.new)
      tenant, path = case object
      when ::Repository
        [object.resolve_tenant, "Repository"]
      when ::Organization
        [object.business, "Organization"]
      when ::User
        object.enterprise_managed_business
      when REPOSITORY_ID_METHOD
        [::Repositories::Public.resolve_tenant(id: object.repository_id), "method_repository_id"]
      when REPOSITORY_METHOD
        [object.repository&.resolve_tenant, "method_repository"]
      when RESOLVE_TENANT_METHOD
        [object.resolve_tenant, "method_resolve_tenant"]
      when OWNER_METHOD
        owner = object.owner
        if owner&.organization?
          [owner&.business, "method_owner_organization"]
        else
          [owner&.enterprise_managed_business, "method_owner_user"]
        end
      else
        [nil, "unknown"]
      end

      inspector.log(tenant, {
        "resolve_path" => path,
        "source_type" => object.class.name,
      })

      tenant
    end
  end
end
