# typed: true
# frozen_string_literal: true

require_relative "../runner"
# Do not require anything else here. If you need something for your runner, put that in `self.run`.
# This makes sure the boot time of our seeds stays low.

module Seeds
  class Runner
    class FeaturePreviews < Seeds::Runner
      def self.help
        <<~HELP
        Creates sample feature preview items for development and testing.
        This will create several feature previews with descriptions, images, and feedback links.
        You can customize the features created by modifying the `create_sample_features` method.
        HELP
      end

      def self.run(options = {})
        create_sample_features

        puts "Done seeding feature previews."
      end

      def self.create_sample_features
        features_to_create = [
          {
            public_name: "Enhanced Code Navigation",
            slug: "enhanced_code_navigation",
            feature_flag_name: "enhanced_code_navigation",
            description: "Provides improved code navigation and search capabilities across repositories.\nThis enables features like:\n- Jump to Definition\n- Find All References\n- Code Outline View",
            image_link: "/images/modules/search/dark.png",
            feedback_link: "https://github.com/github/feedback/discussions",
          },
          {
            public_name: "Advanced Issue Templates",
            slug: "advanced_issue_templates",
            feature_flag_name: "advanced_issue_templates",
            description: "Create more sophisticated issue templates with conditional fields and validation.",
            image_link: "/images/cropped_banner.jpg",
            feedback_link: "https://github.com/github/feedback/discussions",
          },
          {
            public_name: "Repository Insights Dashboard",
            slug: "repository_insights_dashboard",
            feature_flag_name: "repository_insights_dashboard",
            description: "View detailed analytics and insights about your repository activity and performance.",
            feedback_link: "https://github.com/github/feedback/discussions",
          }
        ]

        features_to_create.each do |feature_attrs|
          Feature.where(slug: feature_attrs[:slug]).destroy_all
          Seeds::Objects::FeatureFlag.enable(feature_flag: feature_attrs[:feature_flag_name])
          Feature.create!(feature_attrs)
          puts "Created feature preview: #{feature_attrs[:public_name]}"
        end
      end
    end
  end
end
