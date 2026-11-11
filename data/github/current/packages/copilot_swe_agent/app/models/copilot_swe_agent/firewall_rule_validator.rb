# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  # Shared validation logic for firewall allowlist rules.
  # Rules can be domains, IPv4/IPv6 addresses, or URLs (http/https, ports 80/443 only).
  module FirewallRuleValidator
    DOMAIN_PATTERN = T.let(
      /\A([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.([a-z]{2,63})\z|\A[a-z0-9][a-z0-9\-]{0,61}\z/,
      Regexp
    )

    # Validates a single firewall rule string.
    # Returns [true, nil] on success, [false, error_message] on failure.
    sig { params(rule: String).returns([T::Boolean, T.nilable(String)]) }
    def self.validate_rule(rule)
      trimmed = rule.strip
      return [true, nil] if trimmed.empty?

      # Check if it's an IP address (IPv4 dotted-quad or IPv6)
      if trimmed.match?(/\A[\d.:a-fA-F]+\z/)
        begin
          IPAddr.new(trimmed)
          return [true, nil]
        rescue IPAddr::InvalidAddressError
          return [false, "Invalid IP address '#{trimmed}'. Must be a valid IPv4 or IPv6 address"]
        end
      end

      # Check if it's a URL
      if trimmed.include?("://")
        return validate_url(trimmed)
      end

      # Check if it's a valid domain
      unless DOMAIN_PATTERN.match?(trimmed.downcase)
        return [false, "Invalid rule '#{trimmed}'. Must be a valid domain, IP address, or URL"]
      end

      [true, nil]
    end

    # Validates an array of firewall rules.
    # Returns [true, nil] on success, [false, error_message] on first failure.
    sig { params(rules: T.nilable(T::Array[String])).returns([T::Boolean, T.nilable(String)]) }
    def self.validate_rules(rules)
      return [true, nil] if rules.nil? || rules.empty?

      rules.each do |rule|
        valid, reason = validate_rule(rule)
        return [valid, reason] unless valid
      end

      [true, nil]
    end

    sig { params(url: String).returns([T::Boolean, T.nilable(String)]) }
    private_class_method def self.validate_url(url)
      parsed_url = URI.parse(url)

      unless %w[http https].include?(parsed_url.scheme)
        return [false, "Invalid URL scheme in '#{url}'. Only http and https are supported"]
      end

      if parsed_url.host.blank?
        return [false, "URL '#{url}' must have a non-empty host"]
      end

      if parsed_url.port && ![80, 443].include?(parsed_url.port)
        return [false, "Invalid rule defined. Only ports 80 and 443 are supported in URL rules. '#{url}' uses port '#{parsed_url.port}'"]
      end

      if parsed_url.userinfo.present?
        return [false, "URLs with a username or password component are not allowed as could contain secrets"]
      end

      if parsed_url.query
        return [false, "URL has query parameters, not allowed as could contain secrets"]
      end

      [true, nil]
    rescue URI::InvalidURIError
      [false, "Failed to parse URL: #{url}"]
    end
  end
end
