# typed: true
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class UnmatchStackCountComparator

    attr_reader :tech_stack

    UNMATCH_TECH_STACK_CATEGORIES = T.let(["continuous integration", "testing"], T::Array[String])

    def initialize(tech_stack)
      @tech_stack = tech_stack
    end

    # Return true, if given categories is applicable for this comparator
    sig { params(categories: T::Array[String]).returns(T::Boolean) }
    def self.applicable?(categories)
      return true if categories.empty?

      categories.any? { |category| UNMATCH_TECH_STACK_CATEGORIES.include?(category.downcase) }
    end

    # Returns 0, 1, -1 based upon unmatch tech stack count of two templates
    sig { params(template_a: RepositoryActions::Onboarding::Template, template_b: RepositoryActions::Onboarding::Template).returns(Integer) }
    def compare(template_a, template_b)
      return 0 if tech_stack.empty?
      return -1 if template_a.tech_stack.length - template_a.matched_tech_stack(tech_stack).length == 0 if template_a.tech_stack.length > 0
      return 1 if template_b.tech_stack.length - template_b.matched_tech_stack(tech_stack).length == 0 if template_b.tech_stack.length > 0
      0
    end
  end
end
