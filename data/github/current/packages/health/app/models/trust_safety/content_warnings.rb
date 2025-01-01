# typed: true
# frozen_string_literal: true

module TrustSafety
  class ContentWarnings
    class ValidationError < StandardError
    end

    class << self
      def categories
        @@content_warnings ||= load_json
        @@content_warnings.keys
      end

      def validate_category(category, allow_nil: false)
        return if allow_nil && category.nil?
        @@content_warnings ||= load_json
        return if @@content_warnings.keys.include?(category)
        raise ValidationError.new("Invalid content warning category: #{category}")
      end

      def validate_sub_category(category, sub_category, allow_nil: false)
        return if allow_nil && category.nil? && sub_category.nil?
        @@content_warnings ||= load_json
        return if sub_category == "custom"
        return if @@content_warnings.dig(category, "sub_categories").nil? && sub_category.nil?
        return if @@content_warnings.dig(category, "sub_categories")&.keys&.include?(sub_category)
        raise ValidationError.new("Invalid content warning sub category for #{category}: #{sub_category}")
      end

      def type_for(category)
        @@content_warnings ||= load_json
        @@content_warnings.dig(category, "type")
      end

      def label_for(category)
        @@content_warnings ||= load_json
        @@content_warnings.dig(category, "label")
      end

      def purpose_for(category)
        @@content_warnings ||= load_json
        @@content_warnings.dig(category, "purpose")
      end

      def title_for(category)
        @@content_warnings ||= load_json
        @@content_warnings.dig(category, "title")
      end

      def reason_for(category)
        @@content_warnings ||= load_json
        @@content_warnings.dig(category, "reason")
      end

      def subtitle_for(category, subcategory = nil)
        @@content_warnings ||= load_json
        subtitle = @@content_warnings.dig(category, "subtitle")
        return subtitle if subcategory.nil? || subcategory == "custom"
        subtitle + @@content_warnings.dig(category, "sub_categories", subcategory, "value")
      end

      def category_options
        @@content_warnings ||= load_json
        @@content_warnings.entries.map do |entry|
          [entry[1]["label"], entry[0]]
        end.to_h
      end

      def sub_category_options_for(category)
        @@content_warnings ||= load_json
        @@content_warnings[category]["sub_categories"].entries.map do |entry|
          [entry[1]["label"], entry[0]]
        end.append(%w[Custom custom]).to_h
      end

      def moderation_action_reason_for(category)
        case category
        when "student_pages"
          :TRADEMARK
        when "objectionable_offensive_content"
          :DISCRIMINATORY_CONTENT
        when "mis_dis_information"
          :DISINFORMATION
        when "sexually_explicit_content"
          :SEXUALLY_OBSCENE_CONTENT
        when "violent_content"
          :TOS_VIOLENCE
        else
          :SCOPE_OF_PLATFORM_SERVICES
        end
      end

      private

      CONTENT_WARNINGS_PATH = "config/health/trust_safety/content_warnings.json"

      def load_json
        file_path = Rails.root.join(CONTENT_WARNINGS_PATH)
        GitHub::JSON.load(File.read(file_path))
      end
    end
  end
end
