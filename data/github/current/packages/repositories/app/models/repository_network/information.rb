# typed: true
# frozen_string_literal: true

class RepositoryNetwork
  # Module encapsulating common and useful informational queries about RepositoryNetworks
  # (as opposed to queries for programmatic decision-making about maintenance).
  #
  # The performance characteristics of some of these queries may not be great, nor do
  # they require absolute consistency guarantees, and so they are all run against
  # MySQL read replica's.
  #
  # Example:
  #   RepositoryNetwork::Information.largest[0].name
  #   > "harr999y/boost"
  #
  # Helpful note: a RepositoryNetwork object has a #repositories method, returning the
  # associated Repositories, and a #root method, returning the root repository
  # for this network.
  module Information

    # A query with a giant limit here is likely not especially useful, as well as
    # too taxing (e.g., requesting thousands of RepositoryNetwork objects). We raise
    # this exception if a caller tries one of these. If anyone really wants to
    # attempt a query like this, it can of course still be done, but outside of
    # this module.
    class ExcessiveQuery < Exception
    end

    # Used for ExcessiveQuery limits
    MAX_LIMIT = 1000

    # Returns the RepositoryNetworks with the most pushes. Defaults to returning
    # just the top network.
    #
    #   limit -  The number of RepositoryNetwork objects to return
    #
    # Returns an of array RepositoryNetwork objects.
    def self.most_pushed(limit = 1)
      raise ExcessiveQuery, "Maximum limit is #{MAX_LIMIT}" if limit > MAX_LIMIT

      ActiveRecord::Base.connected_to(role: :reading) do
        RepositoryNetwork.order("pushed_count DESC").take(limit)
      end
    end

    # Return the largest (in terms of disk usage) RepositoryNetworks. Defaults to
    # returning just the top network.
    #
    #   limit - The number of RepositoryNetwork objects to return
    #
    # Returns an array RepositoryNetwork objects
    def self.largest(limit = 1)
      raise ExcessiveQuery, "Maximum limit is #{MAX_LIMIT}" if limit > MAX_LIMIT

      ActiveRecord::Base.connected_to(role: :reading) do
        RepositoryNetwork.order("disk_usage DESC").take(limit)
      end
    end
  end
end
