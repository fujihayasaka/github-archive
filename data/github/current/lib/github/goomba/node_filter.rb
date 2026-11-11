# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Base class for node filters. Node filters are passed each node in a
  # document fragment that matches the string returned by #selector.
  class NodeFilter < Filter
    # Called before the document is serialized to HTML. Override this method to
    # scan the DOM for any content you need for processing (e.g., to find all
    # usernames ahead of time so that a single DB query can be used to fetch
    # all the mentioned users).
    #
    # document - The Goomba::DocumentFragment that will be processed.
    def scan(document)
    end

    # The main filter entry point.
    #
    # node - The current Goomba::Node.
    #
    # Possible return values:
    #
    # nil              - leaves the node unmodified and continues calling other
    #                    filters
    # node             - same as nil
    # false            - removes the node
    # String           - parses the String as a DocumentFragment and replaces
    #                    the node
    # new Node         - replaces the node
    # DocumentFragment - replaces the node
    def call(text)
      raise NotImplementedError
    end

    # Called when the filter is initialized. If this returns true, the HTML
    # returned by this filter will not be processed by any other filters in
    # the pipeline.
    def halt_further_filters?
      false
    end

    # Called once the document has been fully processed. Override this method
    # to perform cleanup.
    def finished
    end

    # Perform a filter on html with the given context.
    #
    # html - An HTML String.
    #
    # Returns a filtered HTML String and may modify the result Hash.
    def self.to_html(html, context = nil, result = nil)
      doc = Goomba::DocumentFragment.new(html)
      filter = self.new(context, result)
      filter.scan(doc)
      output = doc.to_html(filters: [filter])
      filter.finished
      output
    end

    # Returns whether authorization checks are safe to run based on context[:stage] and context[:caching] values.
    # This should not be used if a filter doesn't perform any authorization checks, and does not check any
    # filter-specific context values.
    def self.safe_authorization_checks?(context)
      case context[:stage]
      when :input_transformation
        # context[:stage] == :input_transformation is set when the pipeline is executing filters pre-cache.
        # authorization checks should not be run pre-cache when caching is enabled
        !context[:caching]
      when :post_processing
        # context[:stage] == :post_processing is set when the pipeline is executing filters post-cache.
        # authorization checks should only be run post-cache when caching is enabled
        context[:caching]
      else
        # if context[:stage] is any other value, return true whether caching is enabled or not.
        # some example scenarios and expected values:
        # - generating filters' cache keys for a pipeline run (:cache_key_generation)
        # - the filter isn't being run from a pipeline execution (nil)
        true
      end
    end

    protected

    def find_node_ancestor(node, selector)
      parent = node.try(:parent)
      while parent && !parent.matches(selector)
        parent = parent.try(:parent)
      end

      parent
    end

    private

    def is_text_node?(node)
      node&.is_a?(Goomba::TextNode)
    end

    def is_element_node?(node)
      node&.is_a?(Goomba::ElementNode)
    end
  end
end
