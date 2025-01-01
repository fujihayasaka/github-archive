# typed: true
# frozen_string_literal: true

module GHECAdmin
  autoload :EnterpriseDormantUsersExport, "ghec_admin/enterprise_dormant_users_export"
  autoload :EnterpriseUsersExport, "ghec_admin/enterprise_users_export"
  autoload :Storage, "ghec_admin/storage"
  autoload :S3Storage, "ghec_admin/storage"
  autoload :AzureStorage, "ghec_admin/storage"
end
