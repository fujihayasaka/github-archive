# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module GitHub::Goomba::Async
  # Processes project references generated in GitHub::Goomba::ProjectMentionFilter,
  # replacing the tags with the appropriate result when necessary.
  #
  # Read the documentation of GitHub::Goomba::ProjectMentionFilter first to note
  # how link target references are generated.
  #
  # Project link target references are regular <a> tags with the gh:project-mention attribute.
  # There are two cases with link target references:
  #
  # 1. The HTML content of the link exactly matches the link target, such as <a
  #    href="https://github.com/orgs/github/projects/1/views/1"
  #    gh:project-mention="{…}">https://github.com/orgs/github/projects/1/views/1</a>.
  #    This will occur any time a link to a project is pasted into
  #    a Markdown document bare, as our Markdown processor will autolink the
  #    URL. A user could also manually write such a link.
  #
  # 2. The HTML content of the link does not match the link target, such as <a
  #    href="https://github.com/orgs/github/projects/1/views/1"
  #    gh:project-mention="{…}">See here</a>. This will happen any other time a
  #    link to a project is created.
  #
  # It's worth noting that there's nothing special about the parsed data in the
  # gh:project-mention attribute — we parsed the data out of the URL at the time
  # we added the attribute, so we save ourselves work by not reparsing the URL
  # in this filter, as we need access to the data in both #async_scan and #call.
  #
  #
  # HTML content matches link target
  # --------------------------------
  #
  # In this common case, we note that the href tag matches the inner HTML of the
  # anchor. As long as the referenced project actually exists, we replace the
  # anchor with a full-blown "project link", which contains additional metadata
  # tags for our JavaScript to show the project title in a popup.
  #
  # HTML content does not match link target
  # ---------------------------------------
  #
  # In this less common case, we only add hovercard data attributes, and return anchor tag as
  # is. The result is that the user's link works as they intended, and that any content inside the
  # link was processed by the rest of the pipeline as expected, but that we still create project
  # references for the link.
  #
  class ProjectMentionFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers
    include OcticonsHelper
    include EscapeHelper
    include GitHub::Memoizer

    SELECTOR = Goomba::Selector.new(match: "a[gh|project-mention]")
    MAX_REFERENCES_TO_LOAD = 100

    # Required by GithubReferenceFilter
    def selector
      SELECTOR
    end

    def self.cache_key(context)
      return "project_unfurl_references" if context[:unfurl_references]
      nil
    end

    def self.feature_flags
      [:project_link_unfurling]
    end

    # Required by GithubReferenceFilter
    def self.enabled?(context)
      return false unless current_user = context[:current_user]
      current_user.feature_flag_enabled?(:project_link_unfurling, default: false) && context[:unfurl_references]
    end

    def initialize(*args)
      super

      scratch[:project_references] ||= {}
      @rich_unfurl_enabled = context[:unfurl_references]
    end

    # Translates a `<a gh:project-mention="...">` tag into regular HTML.
    def call(node)
      return unless data = JSON.parse(node["gh:project-mention"])
      owner, number = data["owner"], data["number"].to_i

      node.remove_attribute("gh:project-mention")

      project = project_reference(owner, number)
      return unless project

      original_content = node.to_html
      link = generate_project_reference_link(project, node, data)

      project_reference_wrapper(project) do |wrapper|
        wrapper.authorized { link }
        wrapper.unauthorized { original_content }
      end

    end

    def project_mentions
      result[:projects] ||= []
    end

    def project_reference(owner, number)
      key = [owner, number]
      scratch[:project_references][key]
    end

    def async_scan
      timer = Timer.start

      Promise.all(async_scan_nodes).then do
        GitHub.dogstats.distribution("project_reference_mentions.load_references.dist", timer.elapsed_ms)
      end
    end

    def async_scan_nodes
      references_to_load = Set.new

      @nodes.each do |node|
        # Ensure we don't have unbounded growth in the number of references we load
        if references_to_load.count >= MAX_REFERENCES_TO_LOAD
          break
        end

        data = JSON.parse(node["gh:project-mention"])
        owner, number = data["owner"], data["number"].to_i
        references_to_load << [owner, number]
      end

      references_to_load.map do |reference_to_load|
        owner, number = reference_to_load

        loaded_reference = project_reference(owner, number)
        return Promise.resolve(loaded_reference) if loaded_reference

        async_load_project(owner, number)
      end
    end

    def async_load_project(owner, number)
      Platform::Loaders::ActiveRecord
      .load(User, owner, column: :login, case_sensitive: false)
      .then do |user|
        next nil unless user
        Platform::Loaders::ProjectByOwnerNumber.load(user, number).then do |project|
          next nil unless project
          add_project_reference(owner, number, project)
        end
      end
    end

    def generate_project_reference_link(project, node, data)
      href, inner_html = node["href"], node.inner_html
      owner, number, status_update_id, view = data["owner"], data["number"], data["status_update_id"], data["view"]

      components = link_components(project, view, status_update_id)
      attrs = hovercard_attributes(project.id, view, status_update_id)

      # When the href and inner_html are the same, we can replace the node with a richly unfurled link
      # Otherwise, we just add the hovercard attributes to the node to maintain the original intent of the link
      # for example, when a markdown link is used: [My neat link](https://myneat.url)
      if href == CGI.unescapeHTML(inner_html)
        reference = project_link(
          attrs,
          href,
          components[:shorthand] || components[:text],
          before: components[:icon],
        )

        ActionController::Base.helpers.content_tag(:span, reference, { class: "reference" })
      else
        attrs.each_pair do |attr, value|
          node[attr] = value
        end

        node
      end
    end

    def hovercard_attributes(project_id, view = nil, status_update_id = nil)
      params = {}

      params["view"] = view if view
      params["statusUpdateId"] = status_update_id if status_update_id

      query = "?#{params.to_query}" unless params.empty?

      {
        "class" => "issue-link js-issue-link",
        "data-hovercard-url" => "/memexes/#{project_id}/hovercard#{query}",
        "data-hovercard-type" => "project"
      }
    end

    def link_components(project, view = nil, status_update_id = nil)
      {
        text: GitHub::Goomba::TitleMarkdownFilter.call(project.title),
        icon: @rich_unfurl_enabled ? octicon("table", class: "mr-1") : "",
        shorthand: get_object_shorthand(project, view, status_update_id),
      }
    end

    def project_link(attrs, url, text, before: "")
      link = ActionController::Base.helpers.link_to(text, url, attrs)
      EscapeHelper.safe_join([before, link])
    end

    def get_object_shorthand(object, view, status_update_id)
      trailing_text = " (view)" if view.present?
      trailing_text = " (update)" if status_update_id.present?

      "#{object.title}#{trailing_text}"
    end

    private

    # Internal: Retrieves and updates the existing project reference or creates a new one for the given
    #   repo identifier and issue number combination. References are cached in the "scratch" hash
    #   shared between all filters in the pipeline instance.
    #
    # owner_or_nwo - a string name with owner representing the repo.
    # number - an issue/PR number
    # issue - the Issue corresponding to the number, to be cached
    #
    # Returns a Promise that rezolves into an IssueReference
    def add_project_reference(owner, number, project)
      if existing_reference = project_reference(owner, number)
        existing_reference
      else
        key = [owner, number]
        scratch[:project_references][key] = project
        project_mentions << project
        project
      end
    end
  end
end
