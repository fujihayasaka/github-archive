# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class ServiceComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    extend T::Helpers
    include GitHub::Memoizer

    abstract!

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data) }
    attr_reader :data

    sig do
      params(
        repository: Repository,
        data: Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data
      ).void
    end
    def initialize(repository, data)
      @repository = repository
      @data = data
    end

    sig { abstract.returns(T::Boolean) }
    def restricted_by_enterprise_policy?
    end

    sig { abstract.returns(T::Boolean) }
    def restricted_by_security_configuration?
    end

    sig { returns(T::Boolean) }
    def has_mixed_restrictions?
      data.has_mixed_restrictions
    end

    # If the repository has an enforced security configuration, return the security configuration.
    # Otherwise, return nil.
    sig { returns(T.nilable(SecurityConfiguration)) }
    def enforced_security_configuration
      return nil unless repository.owner&.security_configurations_enabled?

      repository_security_configuration = repository.repository_security_configuration
      security_configuration = repository_security_configuration&.security_configuration

      repository_security_configuration&.enforced? ? security_configuration : nil
    end

    sig { returns(T.nilable(Business)) }
    def business
      repository.owner&.business || repository.enterprise_managed_business
    end
  end
end
