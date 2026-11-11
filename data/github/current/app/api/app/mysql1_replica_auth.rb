# typed: true
# frozen_string_literal: true

# Routes the initial current_user load (User model on Mysql1) to the
# MySQL1 replica instead of the primary. This applies to all requests,
# but only switches connections when Rails has set role: :writing
# (e.g., POST/PATCH/DELETE). When the role is already :reading, we skip
# the connected_to_many call to avoid unnecessary stack overhead.
#
# Since current_user is memoized in @current_user, only the first
# call triggers a DB query — subsequent calls return the cached value.
#
# Including classes may override `mysql1_replica_auth_flag` to gate this
# behavior on a vexi flag while a new batch of endpoints is rolled out
# (and rolled back) independently of endpoints already running under the
# always-on default. Returning nil (the default) means "always on".
module Api::App::Mysql1ReplicaAuth
  extend T::Helpers

  requires_ancestor { Api::App }

  def mysql1_replica_auth_flag
    nil
  end

  def current_user
    return @current_user if defined?(@current_user)

    flag = mysql1_replica_auth_flag
    if ActiveRecord::Base.single_database_cluster? || (flag && !FeatureFlag.vexi.enabled?(flag, default: false))
      super
    elsif ActiveRecord::Base.current_role == :reading
      super
    else
      ActiveRecord::Base.connected_to_many([ApplicationRecord::Mysql1], role: :reading) { super }
    end
  end
end
