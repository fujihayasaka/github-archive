# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DsaAccountModerationAction < Platform::Inputs::Base
      description "Fields required for the Digital Services Act during moderation actions"
      visibility :internal

      argument :dsa_source, Enums::DsaSourceType, "The source that discovered the violation requiring moderation", required: true
      argument :dsa_countries, [String], "The countries that the account is to be moderated in.", required: false
      argument :moderation_type, String, "The type of account moderation. SUSPENDED or TERMINATED", required: false
      argument :moderation_end_timestamp, String, "Timestamp of when the moderation will be lifted", required: false
      argument :content_formats, [Enums::DsaContentFormatType], "The format of content that led to account moderation. TEXT and/or IMAGE", required: false
      argument :content_creation_date, Scalars::DateTime, "Date time of when the violating content was created", required: false
      argument :items_reported_to_ncmec, Int, "How many images/videos were reported to NCMEC", required: false
    end
  end
end
