# typed: true
# frozen_string_literal: true

module PackageRegistry
  module Twirp
    module ActionPackages
      # This class represents the result of a resolve action package version request
      # It knows if a result means:
      # - a successful resolution
      # - a fallback to codeload
      # - a failure
      #
      # In case of a successful resolution, it also exposes:
      # - the resolved package id
      # - the resolved package visibility
      # - the resolved semantic version tag
      class Result
        sig { params(result: Proto::RegistryMetadata::V1::ActionPackages::ResolveActionPackageVersionResult).void }
        def initialize(result)
          @result = result
          @action_ref = T.must(result.action_ref)
        end

        sig { returns(T::Boolean) }
        def success?
          @result.outcome == Proto::RegistryMetadata::V1::ActionPackages::ActionPackageResolutionOutcome.lookup(Proto::RegistryMetadata::V1::ActionPackages::ActionPackageResolutionOutcome::VERSION_RESOLVED)
        end

        sig { returns(T::Boolean) }
        def fallback_to_repository_ref?
          @result.outcome == Proto::RegistryMetadata::V1::ActionPackages::ActionPackageResolutionOutcome.lookup(Proto::RegistryMetadata::V1::ActionPackages::ActionPackageResolutionOutcome::PACKAGE_NOT_FOUND)
        end

        sig { returns(T.nilable(Symbol)) }
        def unrecoverable_error
          return nil if success?
          return nil if fallback_to_repository_ref?

          case @result.outcome
          when Proto::RegistryMetadata::V1::ActionPackages::ActionPackageResolutionOutcome.lookup(Proto::RegistryMetadata::V1::ActionPackages::ActionPackageResolutionOutcome::VERSION_NOT_FOUND)
            :version_not_found
          when Proto::RegistryMetadata::V1::ActionPackages::ActionPackageResolutionOutcome.lookup(Proto::RegistryMetadata::V1::ActionPackages::ActionPackageResolutionOutcome::NAMESPACE_RETIRED)
            :namespace_retired
          when Proto::RegistryMetadata::V1::ActionPackages::ActionPackageResolutionOutcome.lookup(Proto::RegistryMetadata::V1::ActionPackages::ActionPackageResolutionOutcome::ACCESS_DENIED)
            :access_denied
          else
            :unknown_error
          end
        end

        sig { returns(String) }
        def action_ref
          @action_ref.semver_ref
        end

        sig { returns(String) }
        def action_nwo
          "#{@action_ref.namespace}/#{@action_ref.name}"
        end

        sig { returns(T.nilable(Integer)) }
        def resolved_package_id
          return nil unless success?

          @resolved_package_id ||= T.must(@result.resolved_package_version).package_id
        end

        sig { returns(T.nilable(Symbol)) }
        def resolved_package_visibility
          return nil unless success?

          @resolved_package_visibility ||= parse_package_visibility(T.must(@result.resolved_package_version&.package_visibility))
        end

        sig { returns(T.nilable(String)) }
        def resolved_semantic_version_tag
          return nil unless success?

          @resolved_semantic_version_tag ||= T.must(@result.resolved_package_version).semantic_version_tag
        end

        private

        sig { params(visibility: T.any(Symbol, Integer)).returns(Symbol) }
        def parse_package_visibility(visibility)
          case visibility
          when ::Proto::RegistryMetadata::V1::Package::Visibility.lookup(::Proto::RegistryMetadata::V1::Package::Visibility::PUBLIC)
            :PUBLIC
          when ::Proto::RegistryMetadata::V1::Package::Visibility.lookup(::Proto::RegistryMetadata::V1::Package::Visibility::INTERNAL)
            :INTERNAL
          when ::Proto::RegistryMetadata::V1::Package::Visibility.lookup(::Proto::RegistryMetadata::V1::Package::Visibility::PRIVATE)
            :PRIVATE
          else
            # This shouldn't happen unless the proto definition changes.
            # We need an `else` here to satisfy the type checker.
            :INVALID
          end
        end
      end
    end
  end
end
