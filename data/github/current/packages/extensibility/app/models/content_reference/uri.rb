# typed: true
# frozen_string_literal: true

class ContentReference::Uri
  def self.host(uri)
    Addressable::URI.parse(uri).host.downcase
  end
end
