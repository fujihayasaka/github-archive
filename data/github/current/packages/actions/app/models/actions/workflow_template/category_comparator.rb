# typed: strict
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class CategoryComparator

    sig { params(template_a: RepositoryActions::Onboarding::Template, template_b: RepositoryActions::Onboarding::Template).returns(Integer) }
    def compare(template_a, template_b)
      if template_a.category == template_b.category
        0
      elsif template_a.category.casecmp?("automation")
        1
      elsif template_a.category.casecmp?("code scanning")
        1
      else
        0
      end
    end
  end
end
