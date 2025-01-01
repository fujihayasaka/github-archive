# typed: true
# frozen_string_literal: true

class ApplicationCallbackUrl < ApplicationRecord::Collab
  include GitHub::Validations

  extend GitHub::Encoding
  force_utf8_encoding :url

  VALID_APPLICATION_TYPES = %w(OauthApplication Integration)

  # Public: The OauthApplication or Integration that owns this URL
  belongs_to :application, polymorphic: true

  # The matching strategy can be selected by the owner of an app and controls
  # how we determine that a `redirect_uri` is valid for the app being
  # authorized during the OAuth flow.
  # Useful built-in methods include:
  #
  # Predicates:
  # callback_url.permissive_matching_strategy?
  # callback_url.strict_matching_strategy?
  #
  # Setters:
  # callback_url.permissive_matching_strategy!
  # callback_url.strict_matching_strategy!
  #
  # Scopes:
  # ApplicationCallbackUrl.permissive
  # ApplicationCallbackUrl.strict
  enum :matching_strategy, { permissive: 0, strict: 1 }, suffix: true

  validates :application_type, inclusion: { in: VALID_APPLICATION_TYPES }

  validates :url,
    presence: true,
    unicode3: true,
    uniqueness: { scope: [:application_type, :application_id], case_sensitive: false }

  validates_with IntegrationUrlValidator

  default_scope { order(:id) }

  def default?
    return false unless persisted?
    id == application.application_callback_urls.pluck(:id).first
  end

  # Public: The value of the `url` attribute. If the app is syncable to Proxima and has
  # a templated URL, we will interpolate the hostname into the URL (e.g., `https://{hostname}/callback` ->
  # `https://staffship01-ghe.com/callback`).
  #
  # Returns: String
  def url
    return super unless errors.blank? && super.is_a?(String) # Satisfies Sorbet's check during invalid states
    return super unless ::ProximaAppRequest::TenantScopedUrl.should_generate?(app: application, url: super)

    ::ProximaAppRequest::TenantScopedUrl.generate(super, application)
  end

  # Public: The value of the `url` attribute stored in the DB with forced UTF-8 encoding
  #
  # Returns: String
  def raw_url
    value = read_attribute(:url)

    # Borrowed from GitHub::Encoding.force_utf8_encoding
    if value.respond_to?(:force_encoding) && value.encoding != ::Encoding::UTF_8
      value.force_encoding(GitHub::Encoding::UTF8)
    end

    value
  end
end
