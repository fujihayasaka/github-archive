# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class SecretScanningPartnerMetadataComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    include ServiceComponentMethods

    sig { override.returns(T::Boolean) }
    def restricted_by_enterprise_policy?
      false
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_security_configuration?
      false
    end

    sig { returns(T::Boolean) }
    def is_currently_enabled?
      data.secret_scanning_partner_metadata_enabled
    end

    sig { returns(T::Boolean) }
    def blocked_by_in_progress_setting?
      data.secret_scanning_partner_metadata_blocked_by_in_progress_setting
    end
  end
end
