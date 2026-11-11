# typed: true
# frozen_string_literal: true

# Constants used in Trust & Safety moderation actions for compliancy with the Digital Services Act
module DsaConstants
  extend self

  ZENDESK_SUBDOMAIN_OPTIONS = T.let(%w[github github1566843683].freeze, T::Array[String])
  ZENDESK_TICKET_URL_PATTERN = T.let(%r{\Ahttps?://([a-z0-9-]+)\.zendesk\.com/agent/tickets/(\d+)(?:[/?#].*)?\z}i, Regexp)

  TOS_MODERATION_REASON_OPTIONS = T.let([
    ["CSAM", :CSAM],
    ["Violent Content", :VIOLENT_CONTENT],
    ["Discriminatory Content", :DISCRIMINATORY_CONTENT],
    ["User Care", :USER_CARE],
    ["TVEC", :TVEC],
    ["Violence", :TOS_VIOLENCE],
    ["Sexually Obscene Content", :SEXUALLY_OBSCENE_CONTENT],
    ["SPAM", :SPAM],
    ["Disruptive Content", :DISRUPTIVE_CONTENT],
    ["Malware", :MALWARE],
    ["Phishing", :PHISHING],
    ["Harassment", :HARASSMENT],
    ["Misuse of PII", :MISUSE_OF_PII],
    ["Disinformation", :DISINFORMATION],
    ["Scope of Platform Services", :SCOPE_OF_PLATFORM_SERVICES],
    ["COPPA", :COPPA],
    ["Impersonation", :IMPERSONATION],
    ["Trafficking/NCII/Solicitation", :TRAFFICKING_NCII_SOLICITATION],
    ["Trademark", :TRADEMARK]
  ].freeze, T::Array[[String, Symbol]])

  CONTENT_FORMAT_OPTIONS = T.let([
    ["Text", :TEXT],
    ["Image", :IMAGE]
  ].freeze, T::Array[[String, Symbol]])

  SOURCE_OPTIONS = T.let([
    ["Detected by DSA Report", :DSA_REPORT],
    ["Detected by User Report", :USER_REPORT],
    ["Detected by Automated Scan", :SCAN_DETECTION],
    ["Detected by Staff", :STAFF_DETECTION]
  ].freeze, T::Array[[String, Symbol]])

  SUBMISSION_SKIPPABLE_VALUES = T.let(%w[ACCOUNT_TAKEOVER HIDE_FROM_PUBLIC OTHER].freeze, T::Array[String])

  sig { params(url: T.nilable(String)).returns(T.nilable(T::Hash[Symbol, String])) }
  def extract_zendesk_ticket_fields(url)
    return nil if url.blank?

    match = url.match(ZENDESK_TICKET_URL_PATTERN)
    return nil if match.nil?

    zendesk_subdomain = match[1]&.downcase
    zendesk_ticket_id = match[2]

    return nil if zendesk_subdomain.blank? || zendesk_ticket_id.blank?
    return nil unless ZENDESK_SUBDOMAIN_OPTIONS.include?(zendesk_subdomain)

    {
      zendesk_subdomain: zendesk_subdomain,
      zendesk_ticket_id: zendesk_ticket_id,
    }
  end
end
