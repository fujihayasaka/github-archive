# typed: true
# frozen_string_literal: true

class Hook::Payload::GollumPayload < Hook::Payload

  def to_payload_hash
    {
      pages: hook_event.updates.map do |update|
        page = find_page(update)
        {
          page_name: page.name,
          title: page.title,
          summary: page.summary,
          action: update[:action],
          sha: update[:sha],
          html_url: url(page),
        }
      end,
    }
  end

  private

  def wiki
    hook_event.repository.unsullied_wiki
  end

  def find_page(update)
    wiki.pages.find(update[:page_name], update[:sha]) || wiki.pages.find(update[:page_name])
  end

  def url(page)
    "%s/wiki/%s" % [hook_event.repository.permalink, u(GitHub::Unsullied::Page.cname(page.name))]
  end

  # Escapes a URL fragment, allowing only "/"'s
  #
  # s - The String fragment to escape.
  #
  # Returns an escaped String.
  def u(s)
    return "" if s.blank?
    escaped = CGI.escape(s)
    escaped.gsub! /%2F/, "/"
    escaped
  end

end
