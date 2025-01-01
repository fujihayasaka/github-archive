# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class BusinessResolver
    extend T::Sig

    private_class_method :new

    # Returns the business containing the given entity regardless of environment.
    sig { params(entity: T.any(::Repository, ::User)).returns(T.nilable(::Business)) }
    def self.resolve_for(entity)
      return GitHub.global_business if GitHub.single_business_environment?

      if entity.is_a?(::Repository)
        resolve_for_repository(entity)
      elsif entity.is_a?(::User)
        resolve_for_user(entity)
      else
        raise "entity must be a #{::Repository} or #{::User}"
      end
    end

    sig { params(entity: ::Repository).returns(T.nilable(::Business)) }
    private_class_method def self.resolve_for_repository(entity)
      resolve_for_user(T.must(entity.owner))
    end

    sig { params(entity: ::User).returns(T.nilable(::Business)) }
    private_class_method def self.resolve_for_user(entity)
      if entity.organization?
        resolve_for_organization(T.cast(entity, ::Organization))
      elsif entity.user?
        entity.enterprise_managed_business if entity.is_enterprise_managed?
      else
        raise "#{::User} entity must be an organization or vanilla user"
      end
    end

    sig { params(entity: ::Organization).returns(T.nilable(::Business)) }
    private_class_method def self.resolve_for_organization(entity)
      entity.business
    end
  end
end
