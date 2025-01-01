# typed: false
# frozen_string_literal: true

module TipsHelper
  # Public: Returns a String with key:value pairs autolinked to the new query. This is
  # only generated from content we control, so it can be considered html_safe.
  #
  # tip        - The original tip text as String
  # components - Array of components from an existing parsed search query.
  #
  # Example
  #
  #   render_link("Find mentions:dewski") do |components|
  #     query = Search::Queries::AuditLogQuery.stringify(components)
  #     urls.settings_org_audit_log_path(organization, :q => query)
  #   end
  #
  # Returns String
  def render_link(tip, components: nil)
    regex = tip.match(/([\w<>\/-]+):([\w\.<>\/-]+[^\.\s])/)

    # Not everything needs a key:value.
    return tip.html_safe if regex.nil? # rubocop:disable Rails/OutputSafety

    key_value_pair = regex[0]
    key   = regex[1]
    value = regex[2]

    components = Array(components)
    components += [[key.to_sym, value]]

    url = yield components

    link = helpers.link_to(key_value_pair, url, class: "Link--inTextBlock")
    tip.gsub(key_value_pair, link).html_safe # rubocop:disable Rails/OutputSafety
  end
end
