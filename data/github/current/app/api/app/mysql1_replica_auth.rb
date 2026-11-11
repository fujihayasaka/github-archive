# typed: true
# frozen_string_literal: true

# Routes the initial current_user load (User model on Mysql1) to the
# MySQL1 replica instead of the primary when the feature flag is enabled.
# This applies to all requests, but only switches connections when Rails
# has set role: :writing (e.g., POST/PATCH/DELETE). When the role is
# already :reading, we skip the connected_to_many call to avoid
# unnecessary stack overhead.
#
# Since current_user is memoized in @current_user, only the first
# call triggers a DB query — subsequent calls return the cached value.
module Api::App::Mysql1ReplicaAuth
  extend T::Helpers

  requires_ancestor { Api::App }

  def current_user
    return @current_user if defined?(@current_user)

    if ActiveRecord::Base.single_database_cluster? || !FeatureFlag.vexi.enabled?(:issues_api_mysql1_replica_auth, default: false)
      super
    elsif ActiveRecord::Base.current_role == :reading
      super
    else
      ActiveRecord::Base.connected_to_many([ApplicationRecord::Mysql1], role: :reading) { super }
    end
  end
end
