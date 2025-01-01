# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class RelNofollowFilter < Filter
    def call
      doc.search("a").each do |element|
        call_element(element)
      end

      doc.to_html
    end

    # A list of hostnames we allow links to without rel="nofollow"
    ALLOWLIST = [
      GitHub.urls.host_name,
    ].map(&:downcase)

    def call_element(element)
      href = element["href"]

      begin
        uri = Addressable::URI.parse(element["href"])
        return if !uri || uri.host.blank?

        host = uri.host.downcase
        return if ALLOWLIST.any? { |h| host == h || host.end_with?(".#{h}") }
      rescue Addressable::URI::InvalidURIError
        # Fall through: add nofollow if we can't work out the URI.
      end

      if element["rel"]
        element["rel"] += " nofollow"
      else
        element["rel"] = "nofollow"
      end

      element
    end
  end
end
