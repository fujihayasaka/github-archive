# typed: strict
# frozen_string_literal: true

# This module encapsulates data and behavior related to analytics, product metrics, and telemetry (e.g., Hydro).
module PullRequest::AnalyticsDependency
  # To prevent the Hydro payload from exceeding 1MB in size, we truncate the merge commit message, we can potentially
  # be of arbitrary length in some cases. Truncating to 2^16 (65536) bytes ensures that it will not exceed ~6% of 1MB.
  HYDRO_MAX_MERGE_COMMIT_MESSAGE_LENGTH = 65536
end
