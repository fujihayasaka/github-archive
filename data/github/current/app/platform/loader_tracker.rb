# typed: true
# frozen_string_literal: true

module Platform
  class LoaderTracker
    @@loaders = {}
    @@staffbar_enabled = false

    def self.reset!
      @@loaders = {}
      @@staffbar_enabled = false
    end

    def self.loaders
      @@loaders
    end

    def self.loader_tags(loader)
      ["loader:#{loader.class.underscored_name}"].concat(loader.dog_tags).concat(loader.graphql_tags)
    end

    # TODO: According to comments in `ignore_association_loads_test.rb`
    # this method probably should be replaced by batch loader(s).
    def self.ignore_association_loads(&block)
      if Rails.env.production?
        # In production, don't ignore the load. Instead, log it to our dashboards.
        block.call
      else
        GitHub::AssociationInstrumenter.track_loads(nil, &block)
      end
    end

    def self.collect_staffbar_details
      @@staffbar_enabled = true

      yield
    ensure
      @@staffbar_enabled = false
    end

    def self.staffbar_enabled?
      @@staffbar_enabled
    end

    def self.track_loader(loader)
      @@loaders[loader.class.underscored_name] ||= [] if staffbar_enabled?
      loader_tags = loader_tags(loader)

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      result =
        GitHub::MysqlInstrumenter.tag_queries(loader_tags) do
          yield
        end

      ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      duration = (ending - start) * 1000

      @@loaders[loader.class.underscored_name] << duration if staffbar_enabled?

      GitHub.dogstats.distribution("platform.loaders.dist.time", duration, tags: loader_tags)
      result
    end
  end
end
