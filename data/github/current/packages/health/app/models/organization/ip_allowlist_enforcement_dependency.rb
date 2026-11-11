# typed: true
# frozen_string_literal: true

module Organization::IpAllowlistEnforcementDependency
  extend T::Helpers

  requires_ancestor { Organization }

  # Public: Is IP allowlisting enabled on the business that owns the organisation?
  #
  # Returns Boolen
  def ip_allowlist_enabled_on_business?
    self.business&.ip_allowlist_enabled?
  end

  # Public: Get the IP allow list entries for the Organization matching the given query.
  #
  # query - String representing the query
  #
  # Returns ActiveRecord::Relation.
  def filtered_ip_allowlist_entries(query: nil)
    IpAllowlistEntry.usable_for(self)
      .for_query(query)
      .order(allow_list_value: :asc)
  end

  # Public: Get the IP allow list entries for any GitHub Apps installed on the
  # Organization matching the given query.
  #
  # query - String representing the query
  #
  # Returns ActiveRecord::Relation.
  def filtered_installed_app_ip_allowlist_entries(query: nil)
    IpAllowlistEntry.installed_for(self)
      .for_query(query)
      .order(allow_list_value: :asc)
  end
end
