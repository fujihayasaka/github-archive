# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ContentWarning < Platform::Objects::Base
      docs_category :meta
      description "The content warning for a repository"

      # This object is a value-object and doesn't have its own permissions.
      # Its visibility is determined by the parent object that references it, e.g. Repository.
      def self.async_api_can_access?(permission, _object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # This object is a value-object and doesn't have its own permissions.
      # Its visibility is determined by the parent object that references it, e.g. Repository.
      def self.async_viewer_can_see?(permission, object)
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      scopeless_tokens_as_minimum

      field :type, String, description: "The type of content warning. E.g. 'interstitial'", null: false
      field :category, String, description: "The content warning' category. E.g. 'mis_dis_information'", null: false
      field :sub_category, String, description: "The content warning's sub category. E.g. 'medical_scientific'", null: true
      field :custom_sub_category, String, description: "The content warning's custom sub category text. E.g. 'dangerous stuff.'", null: true

      field :title,
        String,
        description: "The content warning's title. E.g. 'This page may contain false or misleading information.'",
        null: false

      def title
        TrustSafety::ContentWarnings.title_for(object.category)
      end

      field :sub_title,
        String,
        description: "The content warning's sub title. E.g. 'The information contained in this page has not been verified.'",
        null: true

      def sub_title
        TrustSafety::ContentWarnings.subtitle_for(object.category, object.sub_category)
      end
    end
  end
end
