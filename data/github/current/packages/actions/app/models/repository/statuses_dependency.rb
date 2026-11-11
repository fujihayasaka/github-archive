# typed: false
# frozen_string_literal: true

# Statuses and associated fields and methods
#
# See also: Status
module Repository::StatusesDependency
  extend ActiveSupport::Concern

  included do
    has_many :statuses, inverse_of: :repository
    delete_dependents_in_background :statuses, sharding_key: :repository_id, sharding_value_key: :id
  end

  def combined_status(ref)
    sha = ref_to_sha(ref)

    return nil unless sha

    CombinedStatus.new(self, sha, check_runs: [])
  end
end
