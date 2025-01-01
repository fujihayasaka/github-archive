# typed: true
# frozen_string_literal: true

module GitHub
  module DomainIsolation
    extend T::Generic

    Partitioned = type_template

    # Public: When called, returns the current domain we are operating within
    sig { returns(T.nilable(String)) }
    def self.current_domain
      GitHub.context[:package]
    end

    # Public: Attributes SQL queries executed inside the given block as originating from either:
    # - The given domain (package)
    # - The domain (package) which owns the given type
    sig do
      params(
        type_or_package: T.nilable(Object),
        block: T.proc.returns(T.untyped)
      ).returns(Partitioned)
    end
    def self.within_domain_of(type_or_package, &block)
      return yield if type_or_package.nil?

      package = if type_or_package.is_a?(String) && type_or_package.start_with?("packages/")
        type_or_package
      else
        type_or_package = GitHub.packageowners.package_for_type(type_or_package)
      end

      return yield if package.nil?

      GitHub.context.push(package: type_or_package) do
        ActiveSupport::ExecutionContext.set(package: package) do
          yield
        end
      end
    end
  end
end
