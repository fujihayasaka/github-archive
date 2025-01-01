# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Reference
  # ReferenceFilter is the base class for all filters that perform checks with database resources against transformed
  # HTML content before it is returned to the client.  This class implements boilerplate code to
  # orchestrate resource loading and transform matching reference nodes and should not be used directly.
  # HTML pipeline authorization should be performed using subclasses of this filter.
  #
  # This has primarily been used for Authorization checks, but can be used for any type of check that requires
  # database resources to be loaded and checked against transformed HTML content.
  #
  # Reference filters used for Authorization match and transform HTML elements like
  # <gh:auth-check>
  #  <gh:authorized><p>Authorized user content</p></gh:authorized>
  #  <gh:unauthorized><p>Unauthorized user content</p></gh:unauthorized>
  # </gh:auth-check>
  #
  # This HTML would be handled by a subclass with a "gh|auth-check" selector. After processing, the input
  # HTML element will be replaced by the children of the <gh:authorized> or <gh:unauthorized> element
  # depending on whether the user is authorized to view the content.  A viewer that passes authorization checks will
  # see `<p>Authorized user content</p>` after this filter is run.
  #
  # Reference checks are performed in `#async_scan` by calling `#async_load_resources`, `#check_for_stale_content`,
  # and `#async_check_authorization`, and authorization nodes are transformed in `#call` based on whether each node
  # has passed authorization checks or not. If the content is stale the pipeline will be re-run from scratch avoiding
  # the cache.
  #
  # Subclasses should override `#async_load_resources`, `#check_for_stale_content`, and `#async_check_authorization`.
  # They should not override `#async_scan` or `#call`.  Subclasses notify that a node has passed authorization checks
  # by adding it to the `authorized_nodes` set, which is used by `#call` to determine whether to show authorized or
  # unauthorized content. Tracking authorized nodes in this way allows for efficient lookup during `#call`.
  #
  # - async_load_resources(nodes) should load any resources or data needed to perform authorization checks for each of
  #   the Goomba nodes available in the `nodes` argument, using deferred execution (async) Promises
  # - check_for_stale_content(nodes) should check whether the content retrieved from the cache is stale and should
  #   be re-run.
  # - async_check_authorization(nodes) should perform authorization checks for each of the Goomba nodes available
  #   in the `nodes` argument, using deferred execution (async) Promises.  All nodes that pass authorization checks
  #   must be added to the `authorized_nodes` set.
  #
  # Subclasses can also override `#access_denied(node)` to perform additional tasks when a viewer is not authorized
  # to view the contents of a node.  This method is called before the node is transformed in `#call` and can be
  # used to manipulate the `result` or `scratch` objects to remove objects that a viewer can not access.  For example,
  # `result[:issues]` tracks all of the issue references found while transforming markdown and is used to create
  # issue referenece timeline events when saving or updating markdown content.  If the markdown author references
  # an issue they can not access, we should not create a timeline event and need to remove the issue reference from
  # `result[:issues]`.
  class ReferenceFilter < GitHub::Goomba::Async::NodeFilter
    extend T::Helpers

    # ReferenceFilter is an abstract class
    abstract!

    # Descendant classes must provide a selector
    sig { abstract.returns(Goomba::Selector) }
    def selector; end

    # Goomba will not recursively re-run a filter on content returned by that filter.
    # In dev and test environments, nested reference checks of the same type will trigger this error, e.g.
    # <gh:auth-check-1><gh:authorized><gh:auth-check-1>...</gh:auth-check-1></gh:authorized></gh:auth-check-1>
    #
    # This is not an issue with nested reference checks of different types, the following is ok:
    # <gh:auth-check-1><gh:authorized><gh:auth-check-2>...</gh:auth-check-2></gh:authorized></gh:auth-check-1>
    class RecursiveReferenceError < StandardError; end

    # Override scan so that NodeFilter.to_html is usable for testing reference filters
    def scan(document)
      async_scan_doc(document).sync
    end

    # Scan any nodes matching an reference filter's selector and perform reference checks.  This method should
    # not be overridden.
    # Returns a Promise with no result value.
    def async_scan
      # if there are no nodes to check, we still want to instrument that the filter ran
      # however we give a different result tag so that we can filter out no-op runs if desired
      if @nodes.empty?
        instrument_result("noop", 0.0)
        return Promise.resolve
      end

      timer = Timer.start

      # first load resources
      async_load_resources(@nodes)
        # then ensure that a bot user's integration installation is loaded before checking references
        .then { async_load_installation(repository) }
        # then ensure that the content retrieved isn't stale
        .then { async_check_for_stale_content(@nodes) }
        # then check authorization for each node
        .then { async_check_authorization(@nodes) }
        # then instrument success and failure cases
        .then { instrument_result("success", timer.elapsed_ms(3)) }
        .rescue do |e|
          instrument_result("error", timer.elapsed_ms(3))
          raise e
        end
    end

    # Transform a node based on whether it has passed authorization checks or not.  Authorization is determined by
    # whether the node is in the `authorized_nodes` set, and expects that all authorized nodes have been added to
    # the set by subclasses during `#async_check_authorization`.  This method should not be overridden.
    #
    # Returns the html content under the <gh:authorized> or <gh:unauthorized> element, or an empty string in
    # an error case
    def call(node)
      if authorized_nodes.include?(node)
        content_element = GitHub::Goomba::Reference::AUTHORIZED_ELEMENT
      else
        access_denied(node)
        content_element = GitHub::Goomba::Reference::UNAUTHORIZED_ELEMENT
      end

      content = node.select(content_element.gsub(":", "|")).first

      # detect and handle nested same-type reference checks
      if content&.select(selector)&.any?
        # in dev and test, raise an exception to highlight the error case
        raise RecursiveReferenceError if Rails.env.development? || Rails.env.test?

        # in non dev/test environments, return an empty string as a more graceful handling of this case
        return ""
      end

      content.try(:inner_html) || ""
    end

    # Load resources for reference checks relating to the nodes found by this filter.
    # Subclasses should override this method to load resources (DB models, data from external services)
    # that will be needed in #async_check_authorization and #async_check_for_stale_content
    def async_load_resources(nodes)
      Promise.resolve
    end

    # Check viewer references for the nodes found by this filter.
    # Subclasses should override this method and add nodes whose data fully passes authorization checks
    # to the `authorized_nodes` set.
    def async_check_authorization(nodes)
      Promise.resolve
    end

    # Validate whether the content is current
    # Subclasses should override this method if there is the potential for stale content
    # to be retrieved from the cache
    # Raise a StaleReferenceError on failure to trigger a pipeline re-run
    def async_check_for_stale_content(nodes)
      # raise StaleReferenceError
      Promise.resolve
    end

    # Perform additional tasks when access to a nodes contents is not authorized for the current
    # viewer.
    # Subclasses should override this method to do things like remove data from the result object
    def access_denied(node); end

    # The set of nodes which this filter matches on and which have passed reference checks.
    def authorized_nodes
      @authorized_nodes ||= Set.new
    end

    # Returns a conditional access policy filter if one is available to
    # filter resources that are not accessible to the current viewer.
    def cap_filter
      return @cap_filter if defined?(@cap_filter)

      @cap_filter = context[:cap_filter]
      if @cap_filter.is_a?(Hash) && @cap_filter.has_key?(:cap_filter)
        @cap_filter = @cap_filter[:cap_filter]
      end

      @cap_filter
    end

    # Returns the current user to use for reference checks.
    # Prefers context[:viewer] if set, otherwise falls back to context[:current_user]
    def current_user
      return context[:viewer] if context.has_key?(:viewer)

      context[:current_user]
    end

    # Returns a map of resources (issues, discussions, etc) that have already
    # been loaded and which were previously set into the pipeline's result object.
    # The map structure looks like
    # {
    #   "Issue" => {
    #     4 => <issue with id 4>
    #     1000 => <issue with id 1000>,
    #     ...
    #   },
    #   "Discussion" => {
    #     16 => <discusssion with id 16>,
    #     ...
    #   },
    #   ...
    # }
    def preloaded_resources
      return @preloaded_resources if defined?(@preloaded_resources)

      @preloaded_resources = {}

      # Find repository-based preloaded resources
      @preloaded_resources["Repository"] = {}

      # add the current repository from context as a preloaded resource if it is available
      if repository.present?
        @preloaded_resources["Repository"][repository.id] = repository
      end

      @preloaded_resources["Issue"] = {}
      result[:issues].try(:each) do |ref|
        issue = ref.belonging
        @preloaded_resources["Issue"][issue.id] = issue

        # add the issue's repository as a preloaded resource if available
        if issue.association(:repository).loaded?
          repository = issue.repository
          @preloaded_resources["Repository"][repository.id] ||= repository
        end
      end

      @preloaded_resources["Discussion"] = {}
      result[:discussions].try(:each) do |ref|
        discussion = ref.belonging
        @preloaded_resources["Discussion"][discussion.id] = discussion

        # add the discussion's repository as a preloaded resource if available
        if discussion.association(:repository).loaded?
          repository = discussion.repository
          @preloaded_resources["Repository"][repository.id] ||= repository
        end
      end

      # Find organization-based preloaded resources
      @preloaded_resources["Organization"] = {}
      if organization = context[:organization]
        @preloaded_resources["Organization"][organization.id] = organization
      end

      @preloaded_resources["Repository"].values.each do |repository|
        next unless repository.association(:owner).loaded?
        next unless repository.owner.is_a?(Organization)
        @preloaded_resources["Organization"][repository.owner.id] ||= repository.owner
      end

      @preloaded_resources["Team"] = {}
      result[:mentioned_teams].try(:each) do |team|
        @preloaded_resources["Team"][team.id] ||= team

        if team.association(:organization).loaded?
          organization = team.organization
          @preloaded_resources["Organization"][organization.id] ||= organization
        end
      end

      @preloaded_resources["Project"] = {}
      result[:projects].try(:each) do |project|
        @preloaded_resources["Project"][project.id] ||= project

        next unless project.association(:owner).loaded?
        next unless project.owner.is_a?(Organization)
        @preloaded_resources["Organization"][project.owner.id] ||= project.owner
      end


      @preloaded_resources
    end

    private

    def instrument_result(result, elapsed_ms)
      GitHub.instrument "goomba.filter.scan", filter: self, duration: elapsed_ms, extra_tags: ["result:#{result}"]
    end
  end
end
