# typed: false
# frozen_string_literal: true
module VarnishHelper

  # Generate page level meta tags with dynamic content
  #
  # These are generated through one helper so that when we're behind Varnish
  # we can inject this with one `esi:include` call instead of multiple serial calls.
  # Every page that needs some sort of request tracking etc, should use this helper.
  #
  # The non-varnished version must match varnish-iris-sidecar.
  # https://github.com/github/varnish-iris-sidecar/blob/cfb119bf4b7d7590e8c77d59fe300166d7709e4a/pkg/esi/routes.go#L258-L260
  def page_meta_tags
    if varnished?
      esi_request_tag("meta")
    else
      tag(:meta, name: "request-id", content: request_id, "data-turbo-transient": true) <<
      tag(:meta, name: "html-safe-nonce", content: html_safe_nonce, "data-turbo-transient": true) <<
      visitor_meta_tag
    end
  end

  def user_currency_tag
    tags = []
    safe_join(tags)
  end

  # Create a hidden input tag with an authenticity token in it.
  #
  # Examples:
  #
  #   csrf_hidden_input_for("/some/path")
  #   => <input type="hidden" data-csrf="true" value="[token]"/>
  #
  #   csrf_hidden_input_for("/some/path", method: :delete)
  #   => <input type="hidden" data-csrf="true" value="[token]"/>
  #
  #   csrf_hidden_input_for("/some/path", class: "js-data-url-csrf")
  #   => <input type="hidden" data-csrf="true" class="js-data-url-csrf" value="[token]"/>
  #
  # The non-varnished version must match varnish-iris-sidecar.
  # https://github.com/github/varnish-iris-sidecar/blob/cfb119bf4b7d7590e8c77d59fe300166d7709e4a/pkg/esi/routes.go#L103-L139
  def csrf_hidden_input_for(path, method: :post, **tag_options)
    if varnished?
      esi_request_tag("rails_csrf_token_form_hidden",
        options: tag_options.merge(
          action_path: path,
          method: method,
        ),
      )
    else
      tag("input", {
        type: "hidden",
        value: authenticity_token_for(path, method: method),
        "data-csrf": true,
      }.merge(tag_options))
    end
  end

  # We override this so CSRF tokens are included in forms during tests.
  # We do this by commenting out the `protect_against_forgery?` check.
  #
  # The non-varnished version must match varnish-iris-sidecar.
  # https://github.com/github/varnish-iris-sidecar/blob/cfb119bf4b7d7590e8c77d59fe300166d7709e4a/pkg/esi/routes.go#L103-L139
  def token_tag(token = nil, form_options: {})
    if varnished?
      esi_request_tag("rails_csrf_token_form_hidden",
        options: {
          name: request_forgery_protection_token,
          action_path: form_options[:action],
          method: form_options[:method],
        },
      )
    else
      if token != false # && protect_against_forgery?
        token ||= form_authenticity_token(form_options: form_options)
        tag(:input, type: "hidden", name: request_forgery_protection_token, value: token)
      else
        ""
      end
    end
  end

  # Render form inputs that help detect spammers.
  #
  # The non-varnished version must match varnish-iris-sidecar.
  # https://github.com/github/varnish-iris-sidecar/blob/73693694ae16622fff4c1924f6b4b1f37c17b89d/pkg/esi/routes.go#L198-L212
  def spamurai_form_signals
    return "" unless GitHub.spamminess_check_enabled?
    if varnished?
      esi_request_tag("spamurai_form_signals")
    else
      timestamp = Timestamp.milliseconds_since_epoch
      text_field_tag("required_field_#{SecureRandom.hex(2)}", nil, { id: nil, hidden: true }) <<
      hidden_field_tag(:timestamp, timestamp, id: nil) <<
      hidden_field_tag(:timestamp_secret, SpamuraiFormSignals.timestamp_hmac(timestamp), id: nil)
    end
  end

  # Decode the given visitor payload for merging it with other data.
  # This validates the HMAC as well. If any invalid data is detected,
  # we return an empty hash so no information is added for the caller.
  #
  # This is used by hydro's browser stats endpoint
  # (https://api.github.com/_private/browser/stats) to fill in data that
  # is sometimes added by the caching tier.
  def decode_visitor_payload(payload, hmac)
    unless SecurityUtils.secure_compare(hmac, OpenSSL::HMAC.hexdigest("sha256", GitHub.visitor_secret, payload))
      return {}
    end

    begin
      decoded = GitHub::JSON.decode(Base64.strict_decode64(payload))
    rescue Yajl::ParseError
      return {}
    end
    unless decoded.is_a?(Hash)
      return {}
    end
    decoded.with_indifferent_access
  end
  module_function :decode_visitor_payload

  private

  def varnished?
    return @varnished if defined?(@varnished)
    @varnished = GitHub.varnish_enabled? && request.headers["X-GitHub-Dynamic-Cache"] == "web"
  end

  # get or generate a nonce that will be stored in response headers and passed to ESI.
  # this should not be returned to users, so Varnish must strip it.
  def varnish_iris_sidecar_nonce
    return @varnish_iris_sidecar_nonce if defined?(@varnish_iris_sidecar_nonce)
    @varnish_iris_sidecar_nonce = response.headers["X-Iris-Sidecar-ESI-Nonce"] || begin
      response.headers["X-Iris-Sidecar-ESI-Nonce"] = SecureRandom.hex(32)
    end
  end

  def varnish_iris_sidecar_request_scope
    return @varnish_iris_sidecar_request_scope if defined?(@varnish_iris_sidecar_request_scope)
    @varnish_iris_sidecar_request_scope = request.headers["X-Iris-Sidecar-Request-Scope"]
  end

  # Generate an ESI include tag to be replaced by Varnish. Should not be called
  # directly outside of this helper.
  def esi_request_tag(func, options: {}, expires_in: 1.day)
    esi_authenticity_key = Rails.application.key_generator.generate_key("esi_authenticity",
                             ActiveSupport::MessageEncryptor.key_len)
    crypt = ActiveSupport::MessageEncryptor.new(esi_authenticity_key, serializer: JSON)

    request_to_encrypt = {
      request_scope: varnish_iris_sidecar_request_scope,
      request_nonce: varnish_iris_sidecar_nonce,
      esi_function: func,
      metadata: options,
    }

    encrypted_request = crypt.encrypt_and_sign(request_to_encrypt, expires_in: expires_in, purpose: :esi)

    # return the full ESI tag to be included in the page.
    # this is the only format that Varnish will allow through
    # and varnish-iris-sidecar knows how to decode this.
    tag("esi:include", src: "/_esi/#{func}?r=#{CGI::escape(encrypted_request)}")
  end

  # Used in other tag generation, should normally not be called directly anywhere.
  def visitor_meta_tag
    return "" unless GitHub.visitor_secret.present?
    data = {
      referrer: referrer,
      request_id: request_id,
      visitor_id: current_visitor.id.to_s,
      region_edge: glb_edge_region,
      region_render: GitHub.server_region,
    }

    encoded_data = Base64.strict_encode64(GitHub::JSON.encode(data))
    encoded_data_hmac = OpenSSL::HMAC.hexdigest("sha256", GitHub.visitor_secret, encoded_data)
    tag(:meta, name: "visitor-payload", content: encoded_data, "data-turbo-transient": true) <<
    tag(:meta, name: "visitor-hmac", content: encoded_data_hmac, "data-turbo-transient": true)
  end
end
