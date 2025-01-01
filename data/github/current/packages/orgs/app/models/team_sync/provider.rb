# typed: true
# frozen_string_literal: true

module TeamSync
  class Provider
    # This should only contain those patterns that are currently supported
    PATTERNS = {
      # https://sts.windows.net/a3350e2e-d5fb-4682-b8ed-5cf081a1e841/
      "azuread" => %r{sts\.windows\.net/(?<id>[a-z0-9\-]+)/}i,

      # http://www.okta.com/exk1alt42ls3GoKdV1d8
      "okta" => %r{www\.okta\.com/(?<id>[a-z0-9]+)}i,
    }

    attr_reader :type, :id

    def initialize(type:, id:)
      @type = type
      @id = id
    end

    def self.detect(issuer:)
      PATTERNS.each do |type, pattern|
        if match = pattern.match(issuer)
          return new(type: type, id: match["id"])
        end
      end
      nil
    end

    def supported_for_org?(organization)
      case type
      when "azuread" then true
      when "okta" then true
      else
        false
      end
    end

    def supported_for_business?(business)
      case type
      when "azuread" then true
      when "okta" then true
      else
        false
      end
    end

    def okta?
      type == "okta"
    end

    def azuread?
      type == "azuread"
    end
  end
end
