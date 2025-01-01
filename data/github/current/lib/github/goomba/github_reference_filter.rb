# typed: false
# frozen_string_literal: true

module GitHub::Goomba
  # TODO: interleave all gh| matches rather than scanning the document
  # separately 'n' times (for n different async_scan filters).

  class GithubReferenceFilter < AsyncOutputFilter
    SELECTOR = Goomba::Selector.new(match: "gh|*, [gh|*]")

    FILTERS_HASH = Hash[[
      Async::TasklistBlockItemFilter,
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
      filters.flat_map(&:feature_flags) + [:goomba_tlb_filter_first]
    end

    def async_call(html)
      doc = Goomba::DocumentFragment.new(html, nil)

      used_filters = Set.new
      # keep track of the tasklist block filter separately, so that we can prepend it to the used_filters if used
      used_tlb_filter = nil

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
        if val.is_a?(Async::TasklistBlockItemFilter) && goomba_tlb_filter_first_enabled?
          used_tlb_filter = val
        else
          used_filters << val
        end
        val.add_node(node)
      end

      # So far, the filters were a hash, now convert them to an array so we can use them.
      fs = used_filters.select { |n| n.is_a?(Async::NodeFilter) }

      # Prepend the TasklistBlockItemFilter if it was used, as we want it to run first. Without investigation, all we
      # know is that when the TasklistBlockItemFilter is run prior to rich issue mentions, the rich issue mention
      # correctly renders unfurled issues, but this is not the case if vice-versa. Ideally, we could define a determinative
      # order for all filters, but this is a low-risk workaround for now.
      # See https://github.com/github/issues-graph/discussions/1985#discussioncomment-6409532 for more details
      fs.unshift used_tlb_filter unless used_tlb_filter.nil?

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

    private def goomba_tlb_filter_first_enabled?
      return false unless context[:entity].is_a?(Repository)

      GitHub.flipper[:goomba_tlb_filter_first].enabled?(context[:entity].owner)
    end
  end
end
