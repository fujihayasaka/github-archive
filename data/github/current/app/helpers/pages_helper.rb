# typed: true
# frozen_string_literal: true

require "oidc"
require "oidc/cache"

module PagesHelper

  OIDCConfiguration = Struct.new(:token_signing_alg_values, :issuer, :signing_keys_endpoint, keyword_init: true)
  OIDCProvider = Struct.new(:business_id, :oidc_provider_key, :client_id, :tenant_id, :configuration, keyword_init: true)

  # Get rid of this and all references when https://github.com/github/actions-fusion/issues/812 is done
  TOKENZ_ISSUERS = ["https://tokenz-production.service.iad.github.net", "https://tokenz-lab.service.iad.github.net", "https://token.actions.githubusercontent.com"]

  # Get pages certificate status for current repository, return nil if pages not configured or certificate not found.
  def get_certificate_status(repository)
    return nil unless repository.page && (repository.page.subdomain || repository.page.cname)

    # skip the request certificate for subdomain when new routing exp feature enabled.
    return nil if !GitHub.enterprise? && repository.page.cname.nil?

    domain = repository.page.cname ? repository.page.cname : repository.page.url.host
    certificate = Page::Certificate.where(domain: domain).last
    return nil unless certificate
    certificate.state&.to_sym
  end

  # Return the alternate form of a domain to be used in as a SAN in a TLS certificate or an empty string (if no SAN should be used).
  #
  # Example:
  #  - given domain.com, returns www.domain.com (because domain.com is an apex domain)
  #  - given www.domain.com, returns domain.com (because domain.com is an apex domain)
  #  - given test.domain.com, would return www.test.domain.com at the condition test.domain.com is an apex domain, "" otherwise
  #
  def get_alt_domain(domain)
    # Check if the domain is an apex domain(ex. "example.com")
    return "www.#{domain}" if GitHubPages::HealthCheck::Domain.new(domain).apex_domain?

    # Check if domain starts with www since www subdomains will have an alternate domain. Custom subdomains will not have an alternative domain
    alt_domain = domain.delete_prefix("www.")
    return alt_domain if domain.downcase.start_with?("www.") && GitHubPages::HealthCheck::Domain.new(alt_domain).apex_domain?
    ""
  end

  # Return the URL to the OIDC token service
  def actions_token_service_url
    if GitHub.multi_tenant_enterprise?
      tenant = GitHub::CurrentTenant.get
      "https://token.actions.#{tenant}.ghe.com"
    elsif !GitHub.enterprise?
      "https://token.actions.githubusercontent.com"
    else
      "https://#{GitHub.host_name}/_services/token"
    end
  end

  # Return the expected OIDC issuer for a given repository
  def actions_token_issuer(repo)
    # It's typically just the token service url
    issuer = actions_token_service_url

    # But it may be customized for an enterprise
    if !GitHub.enterprise? && repo.owner&.organization? && repo.owner.business
      entity = EnterpriseOIDCIssuerUrlCustomisation.get_issuer_policy(repo.owner.business)
      if entity && entity.include_enterprise_name
        issuer += "/#{repo.owner.business.slug}"
      end
    end

    issuer
  end

  def actions_jwt_client_id(repo)
    if GitHub.multi_tenant_enterprise?
      "https://#{GitHub.host_name_with_tenant}/#{repo.owner.login_for_api}"
    else
      "https://#{GitHub.host_name}/#{repo.owner}"
    end
  end

  def determine_issuer_and_signing_url(repo, token)
    # if the issuer claim "iss" from _payload is https://tokenz-production.service.iad.github.net then actions_token_service_url should also be https://tokenz-production.service.iad.github.net
    if repo.feature_enabled?(:pages_oidc_tokenz_special_issuer) || repo.owner&.feature_enabled?(:pages_oidc_tokenz_special_issuer)
      # decode with out validation to get the issuer, this needs to exist until https://github.com/github/actions-fusion/issues/812 is done
      insecure_payload, _header = JWT.decode(token, nil, false)

      if TOKENZ_ISSUERS.include?(insecure_payload["iss"])
        return insecure_payload["iss"], insecure_payload["iss"], "github-pages-tokenz"
      end
    end

    # Default return if the above conditions are not met
    [actions_token_issuer(repo), actions_token_service_url, "github-pages"]
  end

  # return claims if passed header signature validation and payload content validation,
  # otherwise return nil
  def validate_actions_jwt_token(token, repo)

    issuer, signing_url, identifier = determine_issuer_and_signing_url(repo, token)

    oidc_provider = OIDCProvider.new(
      business_id: identifier, # only used for retrieved cached token
      oidc_provider_key: identifier, # used as cache key for the public key, we will use to do validation for GitHub Pages.
      client_id: actions_jwt_client_id(repo), # used to verify aud
      tenant_id: "github-pages",
      configuration: OIDCConfiguration.new(
        token_signing_alg_values: ["RS256"], # algorithm to sign the jwt token
        issuer: issuer, # used to verify aud
        signing_keys_endpoint: "#{signing_url}/.well-known/jwks" # used to retrieve public key
      )
    )

    # This verification gnna check: exp, iat, nb, iss, aud, algorithm, signature
    result = OIDC::TokenValidator.validate_token(token, oidc_provider, verification_options: {
      verify_expiration: true,
      verify_not_before: true,
      verify_iss: true,
      verify_aud: true,
      algorithms: ["RS256"],
      exp_leeway: 300, # seconds
      iss: issuer,
      aud: actions_jwt_client_id(repo)
    })

    # Report the OIDC token validation error, since it's not likely introduce by user.
    unless result.error.nil?
      Failbot.report!(result.error, {
        "gh.business.id" => oidc_provider.business_id
        })
      return nil, result.error
    end

    # verify the token claims sub
    claims_verify_result = validate_actions_jwt_claims(result.claims, repo)
    return nil, claims_verify_result unless claims_verify_result.nil?
    [result.claims, nil]
  end

  def validate_actions_jwt_claims(payload, repo)
    # extra check to ensure we do not bypass empty exp, nbf, iat case
    if payload["nbf"].blank? || !numberish?(payload["nbf"])
      return "nbf invalid"
    elsif payload["exp"].blank? || !numberish?(payload["exp"])
      return "exp invalid"
    elsif payload["iat"].blank? || !numberish?(payload["iat"])
      return "iat invalid"
    end

    # verify iat manually, we are seeing time drift between actions and dotcom (token issued in the future.)
    # give a leeway 300 seconds to ensure issued_at is valid.
    # we cannot do it thru lib https://github.com/jwt/ruby-jwt#issued-at-claim since iat_leeway is removed.
    return "iat invalid" if ("#{payload["iat"]}".to_i(10) - Time.now.to_i).abs > 300

    nil
  end

  def numberish?(value)
    return true if value.is_a?(Integer)
    return true if value.is_a?(String) && !(value.to_i(10) == 0)
    false
  end

  def skip_report_build_error?(annotation)
    filter_errors = [
      /No url found for submodule path '(.*)' in \.gitmodules/m,
      /Error: No such file or directory @/m,
      /Error: The .* theme could not be found/m,
      /did not find expected key while parsing a block mapping/m,
      /control characters are not allowed at line/m,
    ]
    filter_errors.any? { |filter| !filter.match(annotation).nil? }
  end

  # For multi-tenant enterprise, verifies that there are self hosted actions runners which can build pages.
  # Runners can be shared by an organization that owns the repo, or be assigned to the repo itself.
  def actions_runners_available?(repo)
    # For proxima, self-hosted runners are not required
    return true if GitHub.multi_tenant_enterprise?
    if repo.owner.organization?
      resp = Launch::Twirp.self_hosted_runners_client.list_runners(repo.owner)

      total = resp.value&.total_runners || 0
      return true if total > 0
    end

    resp = Launch::Twirp.self_hosted_runners_client.list_runners(repo)

    total = resp.value&.total_runners || 0
    total > 0
  end
end
