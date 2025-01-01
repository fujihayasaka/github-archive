# typed: strict
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class SourceComparator

    # Return true, if given template source is applicable for source comparator
    sig { params(template_source: Integer).returns(T::Boolean) }
    def self.applicable?(template_source)
      template_source == Source::ALL
    end

    # Returns 0, 1, -1 based upon source of two templates.
    sig { params(template_a: RepositoryActions::Onboarding::Template, template_b: RepositoryActions::Onboarding::Template).returns(Integer) }
    def compare(template_a, template_b)
      if template_a.from_owner? && !template_b.from_owner?
        -1
      elsif !template_a.from_owner? && template_b.from_owner?
        1
      else
        0
      end
    end
  end
end
