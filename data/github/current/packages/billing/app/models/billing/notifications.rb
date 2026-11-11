# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    INFO_THRESHOLD = 75
    WARN_THRESHOLD = 90
    ERROR_THRESHOLD = 100
    LEVEL_INFO = "info"
    LEVEL_WARN = "warn"
    LEVEL_ERROR = "error"
    THRESHOLDS = {
      INFO_THRESHOLD => LEVEL_INFO,
      WARN_THRESHOLD => LEVEL_WARN,
      ERROR_THRESHOLD => LEVEL_ERROR
    }

    CODESPACES_SPENDING_LIMIT = "codespaces_spending_limit"
    CODESPACES_COMPUTE_PRODUCT = "codespaces_compute"
    CODESPACES_STORAGE_PRODUCT = "codespaces_storage"

    SHARED_SPENDING_LIMIT = "spending_limit"
    ACTIONS_PRODUCT = "actions"
    GPR_PRODUCT = "packages"
    CODESPACES_PRODUCT = "codespaces"
    SHARED_STORAGE_PRODUCT = "shared_storage"

    AVAILABLE_PRODUCTS = [
      CODESPACES_SPENDING_LIMIT,
      CODESPACES_COMPUTE_PRODUCT,
      CODESPACES_STORAGE_PRODUCT,
      SHARED_SPENDING_LIMIT,
      ACTIONS_PRODUCT,
      GPR_PRODUCT,
      SHARED_STORAGE_PRODUCT
    ]

    AVAILABLE_KEYS = [
      :threshold_entitlements_info,
      :threshold_entitlements_warn,
      :threshold_entitlements_error,
      :threshold_spending_limit_info,
      :threshold_spending_limit_warn,
      :threshold_spending_limit_error,
    ]
  end
end
