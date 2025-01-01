# typed: strict
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class WeightComparator
    extend T::Sig

    sig { params(template_a: RepositoryActions::Onboarding::Template, template_b: RepositoryActions::Onboarding::Template).returns(Integer) }
    def compare(template_a, template_b)
      template_b.weight <=> template_a.weight
    end
  end
end
