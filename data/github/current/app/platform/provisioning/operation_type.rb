# typed: true
# frozen_string_literal: true

# ENUM module storing operation type for a provisioner and user data reconciler
module Platform::Provisioning::OperationType
  PROVISION = :provision
  SUSPEND   = :suspend
  UNSUSPEND = :unsuspend
  UPDATE    = :update
  DELETE    = :delete
end
