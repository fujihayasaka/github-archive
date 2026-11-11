# typed: true
# frozen_string_literal: true

module OauthApplications
  class TransferBannerComponent < ApplicationComponent
    def initialize(application:)
      @application = application
    end

    def render?
      return false unless @application.pending_transfer?

      # Guard against nil target when user is destroyed before async cleanup completes
      transfer_target.present?
    end

    memoize def transfer
      @application.transfer
    end

    memoize def transfer_target
      transfer.target
    end

    memoize def transfer_path
      if transfer_target.organization?
        settings_org_application_transfer_path(transfer_target, transfer)
      else
        settings_user_application_transfer_path(transfer_target, transfer)
      end
    end

    memoize def transfer_path_with_id
      if transfer_target.organization?
        settings_org_application_transfer_path(transfer_target, transfer.id)
      else
        settings_user_application_transfer_path(transfer_target, transfer.id)
      end
    end
  end
end
