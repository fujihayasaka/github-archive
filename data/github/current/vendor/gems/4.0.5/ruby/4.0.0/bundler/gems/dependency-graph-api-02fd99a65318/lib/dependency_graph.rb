require_relative "./dependency_graph_api"

module DependencyGraph
  def self.features
    @features ||= Monolith::Features.new
  end

  def self.rails_cache_error_handler
    -> (method:, returning:, exception:) {
      DependencyGraph.logger.error("Rails/Redis cache error", exception)

      error_class = exception.class.name.underscore
      Instrument.increment("rails_cache.error", error_class: error_class)
    }
  end

  # This is a global switch for writing to and reading frmo the normalized dg_manifest_* tables.
  # Note that when this is true, _both_ the denormalized and normalized tables get data.
  def self.use_normalized_tables?
    # Normalized tables are used in production and Proxima, but not GHES
    !DependencyGraphAPI.enterprise?
  end
end
