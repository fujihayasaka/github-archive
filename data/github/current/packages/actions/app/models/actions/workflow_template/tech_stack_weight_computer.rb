# typed: true
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class TechStackWeightComputer
    attr_reader :tech_stack

    TECH_STACK_WEIGHT = T.let({ "language" => 500, "cloudresource" => 300, "others" => 100 }, T::Hash[String, Integer])
    LANG_SIZE_PERCENTAGE_MIN = 1.0
    SECURITY_TEMPLATE_WEIGHT_MULTIPLIER = 0.20

    def initialize(tech_stack)
      @tech_stack = tech_stack
    end

    # Return weight of template based on upon tech stack match of template category and given tech stack
    def compute(template)
      return 0 if tech_stack.empty?

      matched_tech_stack = template.matched_tech_stack(tech_stack.keys)
      template_non_lang_tech_stack_weight = 0
      template_lang_tech_stack_weight = 0
      template_langs_size_percent = 0
      matched_tech_stack.each do |programming_stack|
        if programming_stack.is_language?
          template_lang_tech_stack_weight = T.must(TECH_STACK_WEIGHT["language"])
          template_langs_size_percent += [tech_stack[programming_stack], (LANG_SIZE_PERCENTAGE_MIN / 100)].max
        elsif programming_stack.is_cloud_resource?
          template_non_lang_tech_stack_weight += T.must(TECH_STACK_WEIGHT["cloudresource"])
        else
          template_non_lang_tech_stack_weight += T.must(TECH_STACK_WEIGHT["others"])
        end
      end

      weight = (template_lang_tech_stack_weight + template_non_lang_tech_stack_weight) * template_langs_size_percent
      if WorkflowTemplateHelper.has_security_category?(template.categories)
        # We nomalize the security template weight as mentioned in the ADR https://github.com/github/c2c-actions/pull/3738.
        weight = weight * SECURITY_TEMPLATE_WEIGHT_MULTIPLIER
      else
        weight
      end
    end
  end
end
