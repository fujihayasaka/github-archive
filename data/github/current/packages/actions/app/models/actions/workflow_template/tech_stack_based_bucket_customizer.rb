# typed: true
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class TechStackBasedBucketCustomizer

    class << self
      def customize_templates(templates, tech_stack:, max_num_of_templates:)
        return 0, templates.first(max_num_of_templates) if tech_stack.empty?

        pick_one_template_for_each_tech_stack(templates, max_num_of_templates, tech_stack)
      end

      private

      def pick_one_template_for_each_tech_stack(templates, max_num_of_templates, tech_stack)
        tech_stack_templates = []
        tech_stack.each do |ts|
          tech_stack_template = templates.find { |template| template.matches_any_tech_stack_names?([ts]) }
          unless tech_stack_template.nil?
            tech_stack_templates << tech_stack_template
            templates -= [tech_stack_template]
          end

          break if tech_stack_templates.length == max_num_of_templates
        end

        [tech_stack_templates.length, (tech_stack_templates + templates).first(max_num_of_templates)]
      end
    end
  end
end
