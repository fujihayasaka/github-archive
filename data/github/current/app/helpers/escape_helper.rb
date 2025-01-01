# typed: false
# frozen_string_literal: true

module EscapeHelper
  extend ActionView::Helpers::OutputSafetyHelper
  include ActionView::Helpers::OutputSafetyHelper

  def html_safe_to_sentence(array)
    array.map do |elt|
      elt.html_safe? ? elt : h(elt.to_s)
    end.to_sentence.html_safe # rubocop:disable Rails/OutputSafety
  end

  def safe_autolink(link, options = {})
    safe_link_to(nil, link, options)
  end

  def safe_uri(link)
    return nil if link.blank?

    uri = Addressable::URI.parse(link)
    uri = Addressable::URI.parse("http://#{link}") if uri.scheme.nil?
    return nil unless %w[http https].include?(uri.scheme)

    uri.to_s
  rescue Addressable::URI::InvalidURIError
    # Possibly an exploit, or maybe just a strange, strange link
    nil
  end

  def safe_link_to(name, link, options = {})
    link = safe_uri(link)
    return nil if link.blank?

    if options[:target].to_s == "_blank"
      rel_tags = %w(noopener noreferrer)
      rel_tags += options[:rel].to_s.split if options[:rel]

      options[:rel] = rel_tags.uniq.join(" ")
    end

    link_to name || link, link, options
  end

  def safe_data_attributes(hash)
    hash.map do |key, value|
      "data-#{h(key.to_s.dasherize)}=\"#{h(value)}\""
    end.join(" ").html_safe # rubocop:disable Rails/OutputSafety
  end

  def safe_onsite_uri(link, domain = request.domain)
    uri = safe_uri(link)
    return nil unless uri

    uri = Addressable::URI.parse(uri)

    safe_url = uri.absolute? &&
        %w[https http].include?(uri.scheme) &&
        uri.userinfo.nil? &&
        uri.domain == domain &&
        (uri.port.nil? || uri.port == request.port)

    return nil unless safe_url
    uri.to_s
  end
end
