# typed: false
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class LanguageBasedDistributionCustomizer

    class << self
      def customize_templates(templates, languages_percentage:, max_num_of_templates:)
        return 0, templates.first(max_num_of_templates) if languages_percentage.empty?

        pick_template_using_linear_distribution(templates, max_num_of_templates, languages_percentage)
      end

      private

      def pick_template_using_linear_distribution(templates, max_num_of_templates, languages_percentage)
        lang_distributed_templates = []
        languages_percentage.keys.each do |language|
          template_count = (languages_percentage[language] * max_num_of_templates).round
          break if template_count == 0
          lang_templates = templates.select { |template| template.matches_any_tech_stack_names?([language.name]) }.take(template_count)
          lang_distributed_templates += lang_templates
          templates -= lang_templates
        end

        [lang_distributed_templates.length, (lang_distributed_templates + templates).first(max_num_of_templates)]
      end
    end
  end
end
