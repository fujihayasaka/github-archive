# typed: strict
# frozen_string_literal: true

class SiteScopedIntegrationInstallation
  module Editors
    class Base
      extend T::Sig

      sig { params(installation: SiteScopedIntegrationInstallation).returns(Result) }
      def validate_capabilities(installation)
        unless Apps::Internal.capable?(:installed_globally, app: installation.integration)
          return Result.failed(:integration_not_capable)
        end

        Result.success(installation)
      end
    end
  end
end
