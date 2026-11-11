# typed: true
# frozen_string_literal: true

module Codespaces
  class Command
    extend T::Helpers
    extend ActiveModel::Callbacks
    include ActiveSupport::Callbacks
    include GitHub::Memoizer

    abstract!

    define_model_callbacks :perform

    set_callback :perform, :around, :collect_metrics
    set_callback :perform, :around, :log_exceptions
    set_callback :perform, :around, :disable_unallowed_clusters

    # Create and call the command with the given arguments.
    def self.call(...)
      T.unsafe(self)
        .new(...).call
    end

    # Call the command. Subclasses should *not* override this. Instead, see
    # #perform.
    def call
      run_callbacks :perform do
        perform
      end
    end

    def self.depends_on_clusters(*clusters, optional: false)
      if optional
        optional_clusters.concat(clusters)
      else
        required_clusters.concat(clusters)
      end
    end

    def self.optional_clusters
      @optional_clusters ||= []
    end

    def self.required_clusters
      @required_clusters ||= []
    end

    protected

    # Perform the command. Subclasses must implement this method.
    sig { abstract.returns(T.anything) }
    def perform; end

    # The name of the command for tracing and stats purposes.
    sig { returns(T.nilable(String)) }
    def name
      self.class.name&.underscore
    end

    # We should be intentional about which tags go to datadog because the more specific tags are, the more expensive they are.
    def dd_tags
      stats_tagger.datadog_tags
    end

    # The tags that should be included in tracing and stats reporting. This will
    # include codespace metadata by default if the command responds to
    # #codespace.
    def tags
      stats_tagger.all_tags.each_with_object({}) do |(k, v), accum|
        accum[k.to_s] = v.to_s
      end
    end

    def stats_tagger
      codespace_for_stats = if respond_to?(:codespace)
        self.send(:codespace)
      else
        @codespace
      end

      vscs_target_for_stats = begin
        if codespace_for_stats
          codespace_for_stats.vscs_target
        elsif respond_to?(:vscs_target)
          self.send(:vscs_target)
        else
          @vscs_target
        end
      end

      @stats_tagger ||= Codespaces::StatsTagger.new(
        codespace: codespace_for_stats,
        vscs_target: vscs_target_for_stats,
        user: @user,
      )
    end

    private

    def collect_metrics
      GitHub.tracer.in_span("#{name}#call", attributes: tags, kind: :internal) do |_span|
        begin
          GitHub.dogstats.distribution_time("#{name}.latency", tags: dd_tags) do
            yield
            GitHub.dogstats.distribution("#{name}.success", 1, tags: dd_tags)
          end
        rescue Codespaces::Client::BadResponseError => e
          GitHub.dogstats.increment "#{name}.perform.errors", tags: dd_tags.concat(["error:#{e.class.name}", "status:#{e.status}"])
          GitHub.dogstats.distribution("#{name}.perform.errors.dist", 1, tags: dd_tags.concat(["error:#{e.class.name}", "status:#{e.status}"]))
          raise e
        rescue => e # rubocop:todo Lint/RescueException
          GitHub.dogstats.increment "#{name}.perform.errors", tags: dd_tags.concat(["error:#{e.class.name}"])
          GitHub.dogstats.distribution("#{name}.perform.errors.dist", 1, tags: dd_tags.concat(["error:#{e.class.name}"]))
          raise e
        end
      end
    end

    def log_exceptions
      begin
        yield
      rescue => e # rubocop:todo Lint/RescueException
        GitHub.logger.error(stats_tagger.all_semconv_tags.merge(:exception => e, "gh.codespaces.command" => name))
        raise e
      end
    end

    def disable_unallowed_clusters
      return yield unless Rails.env.development? || Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

      allowed_clusters = if GitHub.disable_optional_clusters?
        self.class.required_clusters
      else
        self.class.required_clusters + self.class.optional_clusters
      end

      return yield if allowed_clusters.empty?

      disabled_clusters = ApplicationRecord.clusters - allowed_clusters
      ActiveRecord::Base.disable_queries_to_databases(disabled_clusters) do
        yield
      end
    end
  end
end
