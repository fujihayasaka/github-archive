# typed: strict
# frozen_string_literal: true

module Issues
  class UpdateIssueAttributes < T::Struct
    # The new title for the issue.
    prop :title, T.any(UpdateOptions::Keep, String), default: UpdateOptions::Keep

    # The new body for the issue.
    prop :body, T.any(UpdateOptions::Keep, UpdateOptions::Delete, String), default: UpdateOptions::Keep
  end
end
