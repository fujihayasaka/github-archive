# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class DsaRepositoryModerationAction < Platform::Inputs::Base
      description "Fields required for the Digital Services Act during moderation actions"
      visibility :internal

      argument :content_formats, [Enums::DsaContentFormatType], "The format of content that led to repository moderation. TEXT and/or IMAGE", required: false
      argument :dsa_source, Enums::DsaSourceType, "The source that discovered the violation requiring moderation", required: true
      argument :tos_reason, Enums::TosReasonType, "The Terms of Service violating reason requiring moderation", required: true
    end
  end
end
