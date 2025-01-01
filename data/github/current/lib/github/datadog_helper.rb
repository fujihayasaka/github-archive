# typed: true
# frozen_string_literal: true

module GitHub
  module DatadogHelper
    extend ActiveSupport::Concern

    class_methods do
      def datadog_prefix
        # We use const_get(:DATADOG_PREFIX) here rather than calling
        # DATADOG_PREFIX directly because const_get will search ancestors too
        # and find the constant in the base class, rather than throwing an
        # error after not finding the constant in GitHub::DatadogHelper.
        #
        # The `T.unsafe` is here because this module relies on the fact that it
        # will never be used standalone and always be included on a class.
        # According to Ruby's documentation, `const_get`, is an instance method
        # on the `Module` class, and the `Class` class, inherits from module, so
        # we use the escape hatch since calling `Module.const_get` directly
        # isn't really important and the ancestry chain needs to be respected.
        T.unsafe(self).const_get(:DATADOG_PREFIX)
      end
    end

    def datadog_prefix
      # The `T.unsafe` is here because this module relies on the fact that it
      # will never be used standalone and always be included on a class.
      #
      # Because of the ancestry chain issues above, we need it here the escape
      # hatch here as well because the list of potential classes this could be
      # included on is infinite and that's impossible to type.
      T.unsafe(self).class.datadog_prefix
    end

    def datadog_tags
      @datadog_tags ||= []
    end

    def add_datadog_tags(**tags)
      tags.each do |key, value|
        datadog_tags << "#{key}:#{value}"
      end
    end

    alias_method :add_datadog_tag, :add_datadog_tags

    def datadog_metric(key)
      metric = key.to_s
      metric.prepend(datadog_prefix, ".") if datadog_prefix
      metric
    end

    def datadog_count(tags: [], **counts)
      counts.each do |key, value|
        GitHub.dogstats.count(
          datadog_metric(key),
          value,
          tags: datadog_tags + tags,
        )
      end
    end

    def datadog_increment(*keys, tags: [])
      keys.each do |key|
        GitHub.dogstats.increment(
          datadog_metric(key),
          tags: datadog_tags + tags,
        )
      end
    end

    def datadog_gauge(tags: [], **gauges)
      gauges.each do |key, value|
        GitHub.dogstats.gauge(
          datadog_metric(key),
          value,
          tags: datadog_tags + tags,
        )
      end
    end

    def datadog_timing(tags: [], **timings)
      timings.each do |key, value|
        GitHub.dogstats.timing(
          datadog_metric(key),
          value,
          tags: datadog_tags + tags,
        )
      end
    end

    def datadog_timing_since(tags: [], **timings)
      timings.each do |key, value|
        GitHub.dogstats.timing_since(
          datadog_metric(key),
          value,
          tags: datadog_tags + tags,
        )
      end
    end

    def datadog_time(key, tags: [], &block)
      GitHub.dogstats.time(
        datadog_metric(key),
        tags: datadog_tags + tags,
        &block
      )
    end

    def datadog_histogram(tags: [], **histograms)
      histograms.each do |key, value|
        GitHub.dogstats.histogram(
          datadog_metric(key),
          value,
          tags: datadog_tags + tags,
        )
      end
    end

    def datadog_distribution(tags: [], **distributions)
      distributions.each do |key, value|
        GitHub.dogstats.distribution(
          datadog_metric(key),
          value,
          tags: datadog_tags + tags,
        )
      end
    end

    def datadog_distribution_time(key, tags: [], &block)
      GitHub.dogstats.distribution_time(
        datadog_metric(key),
        tags: datadog_tags + tags,
        &block
      )
    end
  end
end
