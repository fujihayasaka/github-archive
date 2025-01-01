# typed: false
# frozen_string_literal: true

module GitHub::Goomba
  # TODO: interleave all gh| matches rather than scanning the document
  # separately 'n' times (for n different async_scan filters).

  class GithubReferenceFilter < AsyncOutputFilter
    SELECTOR = Goomba::Selector.new(match: "gh|*, [gh|*]")

    FILTERS_HASH = Hash[[
      Async::MentionFilter,
      Async::TeamMentionFilter,
      Async::CommitMentionFilter,
      Async::CompareMentionFilter,
      Async::RichIssueMentionFilter,
      Async::ProjectMentionFilter,
      Async::CloseKeywordFilter,
      Async::IssueBlobFilter,
      Async::VideoTagFilter,
      Async::LabelTagFilter,
      Async::AdvisoryMentionFilter,
      Async::CVEMentionFilter,
      Async::SnippetClipboardCopyFilter,
      Async::AlertMentionFilter,
      Async::DependabotAlertMentionFilter,
    ].compact.map { |fc| [fc::SELECTOR, fc] }].freeze

    FILTERS = FILTERS_HASH.values

    def self.cache_key(context)
      filters.map do |filter|
        next unless filter.enabled?(context)
        filter.cache_key(context)
      end.reject(&:blank?).join(":")
    end

    def self.filters
      FILTERS
    end

    def self.filters_hash
      FILTERS_HASH
    end

    def self.feature_flags
      filters.flat_map(&:feature_flags)
    end

    def async_call(html)
      doc = Goomba::DocumentFragment.new(html, nil)

      used_filters = Set.new

      gh_filters = self.class.filters_hash.dup.select do |_, val|
        val.enabled?(context)
      end

      doc.select(SELECTOR).each do |node|
        # detect the github node filter that matches the node. Only one filter should match.
        r = gh_filters.detect { |selector, _| node.matches(selector) }

        next if r.nil?
        selector, val = r

        if val.is_a?(Class)
          # If it isn't already, instantiate the filter class.
          val = gh_filters[selector] = val.new(context, result, scratch)
        end

        used_filters << val
        val.add_node(node)
      end

      # So far, the filters were a hash, now convert them to an array so we can use them.
      fs = used_filters.select { |n| n.is_a?(Async::NodeFilter) }

      timer = Timer.start
      Promise.all(fs.map { |f| f.async_scan }).then do
        GitHub.dogstats.distribution("goomba.warp_pipe.dist.async_scan", timer.elapsed_ms, tags: ["filter:#{self.class.name.demodulize}"])
        result = doc.to_html(filters: fs)
        fs.each do |f|
          f.finished
        end
        result
      end
    end
  end
end
