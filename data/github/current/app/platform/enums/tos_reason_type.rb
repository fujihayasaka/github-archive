# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TosReasonType < Platform::Enums::Base
      description "Represents the Terms of Service (TOS) reason type of a GitHub moderation action event"
      visibility :internal

      value "CSAM", description: "CSAM", value: :CSAM
      value "VIOLENT_CONTENT", description: "Violent Content", value: :VIOLENT_CONTENT
      value "DISCRIMINATORY_CONTENT", description: "Discriminatory Content", value: :DISCRIMINATORY_CONTENT
      value "USER_CARE", description: "User Care", value: :USER_CARE
      value "TVEC", description: "TVEC", value: :TVEC
      value "TOS_VIOLENCE", description: "ToS Violence", value: :TOS_VIOLENCE
      value "SEXUALLY_OBSCENE_CONTENT", description: "Sexually Obscene Content", value: :SEXUALLY_OBSCENE_CONTENT
      value "SPAM", description: "SPAM", value: :SPAM
      value "DISRUPTIVE_CONTENT", description: "Disruptive Content", value: :DISRUPTIVE_CONTENT
      value "MALWARE", description: "Malware", value: :MALWARE
      value "PHISHING", description: "Phishing", value: :PHISHING
      value "HARASSMENT", description: "Harassment", value: :HARASSMENT
      value "MISUSE_OF_PII", description: "Misuse Of Personally Identifiable Information", value: :MISUSE_OF_PII
      value "DISINFORMATION", description: "Disinformation", value: :DISINFORMATION
      value "SCOPE_OF_PLATFORM_SERVICES", description: "Scope Of Platform Services", value: :SCOPE_OF_PLATFORM_SERVICES
      value "COPPA", description: "Children's Online Privacy Protection Act", value: :COPPA
      value "IMPERSONATION", description: "Impersonation", value: :IMPERSONATION
      value "TRAFFICKING_NCII_SOLICITATION", description: "Trafficking NCII Solicitation", value: :TRAFFICKING_NCII_SOLICITATION
      value "TRADEMARK", description: "Trademark", value: :TRADEMARK
      value "OTHER", description: "Other", value: :OTHER
    end
  end
end
