# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class EnterpriseServerUserAccountsUploadSyncState < Platform::Enums::Base

      description "Synchronization state of the Enterprise Server user accounts upload"

      value "PENDING", "The synchronization of the upload is pending.", value: "pending"
      value "SUCCESS", "The synchronization of the upload succeeded.", value: "success"
      value "FAILURE", "The synchronization of the upload failed.", value: "failure"
    end
  end
end
