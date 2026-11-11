# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CodeScanningSecurityAlert < Platform::Objects::Base
      docs_category :code_scanning
      visibility :internal
      description "Represents a code scanning security alert"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      def self.async_api_can_access?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      field :title, String,
        description: "The title of the code scanning security alert."
      field :number, Integer,
        description: "The number of the code scanning security alert."
      field :status, Platform::Enums::CodeScanningSecurityAlertStatus,
        description: "The status of the code scanning security alert (open, fixed or dismissed)."
      field :repository, Platform::Objects::Repository,
        description: "The repository associated with the code scanning security alert.", method: :async_repository
    end
  end
end
