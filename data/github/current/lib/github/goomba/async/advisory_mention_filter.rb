# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async
  class AdvisoryMentionFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers

    SELECTOR = Goomba::Selector.new(match: "gh|advisory-mention, a[gh|advisory-mention]")
    ATTR_SELECTOR = Goomba::Selector.new(match: "a[gh|advisory-mention]")

    def initialize(*args)
      super
      scratch[:repository_advisories] = {}
      scratch[:global_advisories] = {}
    end

    def selector
      SELECTOR
    end

    def async_scan
      Promise.all(@nodes.reduce([]) do |promises, node|
        ghsa_id, global_reference = if node =~ ATTR_SELECTOR
          data = JSON.parse(node["gh:advisory-mention"])
          [data["ghsa_id"], data["global"]]
        else
          [node["ghsa_id"], false]
        end

        if node["plain_text_ghsa"]
          promises.concat([
            load_global_reference(ghsa_id),
            load_repository_reference(ghsa_id)
          ])
        else
          promises.concat([global_reference ? load_global_reference(ghsa_id) : load_repository_reference(ghsa_id)])
        end
      end)
    end

    def load_global_reference(ghsa_id)
      Platform::Loaders::ActiveRecord.load(Vulnerability, ghsa_id, column: :ghsa_id).then do |vulnerability|
        next unless vulnerability&.globally_available?
        # skip if this was already initialized
        next if global_advisories[ghsa_id]

        global_advisories[ghsa_id] = {
          ghsa_id: vulnerability.ghsa_id,
          permalink: vulnerability.permalink,
          hovercard_data: HovercardHelper.hovercard_data_attributes_for_advisory(ghsa_id: vulnerability.ghsa_id),
        }
      end
    end

    def load_repository_reference(ghsa_id)
      Platform::Loaders::PublishedRepositoryAdvisoryByGhsa.load(ghsa_id).then do |advisory|
        next unless advisory
        # skip if this was already initialized or the advisory's repo isn't found
        next if repository_advisories[ghsa_id]
        next unless advisory.repository.present?

        repository_advisories[ghsa_id] = {
          ghsa_id: advisory.ghsa_id,
          advisory: advisory,
        }
        advisory.async_permalink.then do |permalink|
          repository_advisories[ghsa_id][:permalink] = permalink
        end
      end
    end

    def repository_advisories
      scratch[:repository_advisories]
    end

    def global_advisories
      scratch[:global_advisories]
    end

    # Translates a `<gh:advisory-mention>` tag or `<a gh:advisory-mention="...">` tag
    # placed into the node by Goomba::AdvisoryMentionFilter into regular HTML.
    def call(node)
      if node =~ ATTR_SELECTOR
        call_anchor_tag(node)
      else
        call_mention_tag(node)
      end
    end

    def call_mention_tag(node)
      ghsa_id = node["ghsa_id"]

      if global_advisory = global_advisories[ghsa_id]
        advisory_link(global_advisory)
      elsif advisory_data = repository_advisories[ghsa_id]
        repository_resource_reference_wrapper(advisory_data[:advisory]) do |wrapper|
          wrapper.authorized { advisory_link(advisory_data) }
          wrapper.unauthorized { ghsa_id }
        end
      else
        ghsa_id
      end
    end

    def call_anchor_tag(node)
      href, inner_html = node["href"], node.inner_html
      data = JSON.parse(node["gh:advisory-mention"])
      ghsa_id = data["ghsa_id"]
      global_reference = data["global"]
      node.remove_attribute("gh:advisory-mention")

      if global_reference && advisory_data = global_advisories[ghsa_id]
        advisory_link(advisory_data)
      elsif !global_reference && advisory_data = repository_advisories[ghsa_id]
        repository_resource_reference_wrapper(advisory_data[:advisory]) do |wrapper|
          wrapper.authorized { advisory_link(advisory_data) }
          wrapper.unauthorized { node }
        end
      else
        node
      end
    end

    # Create an advisory link
    #
    # advisory - advisory object to link to
    #
    # Returns an html-safe String link (a href) tag
    def advisory_link(advisory_data)
      if advisory_data[:permalink].present?
        ActionController::Base.helpers.link_to(advisory_data[:ghsa_id], advisory_data[:permalink], title: advisory_data[:ghsa_id], data: advisory_data[:hovercard_data])
      else
        ActionController::Base.helpers.content_tag(:span, advisory_data[:ghsa_id], class: "color-fg-muted", title: advisory_data[:ghsa_id])
      end
    end
  end
end
