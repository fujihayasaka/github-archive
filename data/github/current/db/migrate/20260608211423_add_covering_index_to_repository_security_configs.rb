# typed: true
# frozen_string_literal: true

# Adds a covering index on (security_configuration_id, state, organization_id) to
# speed up the per-organization failure counts queried by
# Businesses::SecurityConfigurationsDependency#org_failures(_unscoped), which power
# the enterprise security settings page.
#
# The existing (security_configuration_id, state) index forces a temporary table to
# GROUP BY organization_id and reads from the table rows. Appending organization_id
# lets the index cover the query so MySQL can satisfy the grouping straight from the
# index. EXPLAIN ANALYZE against production data for a very large enterprise (>100k
# repos) dropped this query from ~2.0s to ~0.23s.
#
# The existing (security_configuration_id, state) index is intentionally retained for
# now; it is a prefix of this new index, but dropping it is left for a follow-up once
# this index is validated in production. GitHub/AvoidRedundantIndex is disabled to allow
# that deliberate, temporary overlap.
#
# See https://github.com/github/security-products-enablement/issues/2800
# rubocop:disable GitHub/AvoidRedundantIndex
class AddCoveringIndexToRepositorySecurityConfigs < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    add_index :repository_security_configurations,
      [:security_configuration_id, :state, :organization_id],
      name: "index_repo_sec_configs_on_config_state_org"
  end
end
