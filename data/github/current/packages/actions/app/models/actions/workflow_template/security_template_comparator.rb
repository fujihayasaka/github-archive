# typed: strict
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class SecurityTemplateComparator

    # Move GitHub recommended security templates to top irrespective of weight
    sig { params(template_a: RepositoryActions::Onboarding::Template, template_b: RepositoryActions::Onboarding::Template).returns(Integer) }
    def compare(template_a, template_b)
      return 0 unless WorkflowTemplateHelper::has_security_category?(template_a.categories) && WorkflowTemplateHelper::has_security_category?(template_b.categories)
      if WorkflowTemplateHelper::POPULAR_SECURITY_TEMPLATES.include?(template_a.id.downcase) && (template_a.weight > 0 || template_b.weight == 0)
        -1
      elsif WorkflowTemplateHelper::POPULAR_SECURITY_TEMPLATES.include?(template_b.id.downcase) && (template_b.weight > 0 || template_a.weight == 0)
        1
      else
        0
      end
    end
  end
end
