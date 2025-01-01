# typed: strict
# frozen_string_literal: true

module Actions::WorkflowTemplate
  class CloudComparator
    extend T::Sig

    CLOUD_ORDER = T.let(["microsoft azure", "amazon web services", "google cloud", "hashicorp", "alibaba cloud", "ibm", "tencent cloud", "red hat"].freeze, T::Array[String])

    # Return true for not owner templates with categories list as empty or containing deployment
    sig { params(categories: T::Array[String]).returns(T::Boolean) }
    def self.applicable?(categories)
      categories.empty? || categories.any? { |category| category.casecmp("deployment") == 0 }
    end

    # Returns 0, 1, -1 based on CLOUD_ORDER, if templates are from the same cloud then return -1, 0, 1 based on template id.
    sig { params(template_a: RepositoryActions::Onboarding::Template, template_b: RepositoryActions::Onboarding::Template).returns(Integer) }
    def compare(template_a, template_b)
      return 0 unless WorkflowTemplateHelper::has_deployment_category?(template_a.categories) && WorkflowTemplateHelper::has_deployment_category?(template_b.categories)

      if (template_a.weight == template_b.weight) && (Actions::TopNCloudCustomizer::POPULAR_CLOUD_TEMPLATES.include?(template_a.id) ^ Actions::TopNCloudCustomizer::POPULAR_CLOUD_TEMPLATES.include?(template_b.id))
        Actions::TopNCloudCustomizer::POPULAR_CLOUD_TEMPLATES.include?(template_a.id) ? -1 : 1
      elsif template_a.creator == template_b.creator
        template_a.id.casecmp(template_b.id)
      else
        compare_clouds(template_a.creator, template_b.creator)
      end
    end

    # Returns 0, 1, -1 based upon cloud_order defined in the CLOUD_ORDER
    sig { params(cloud_a: T.nilable(String), cloud_b: T.nilable(String)).returns(Integer) }
    def compare_clouds(cloud_a, cloud_b)
      if cloud_a.nil? || cloud_b.nil?
        cloud_a.nil? ? 1 : -1
      else
        # Sorbet warns when the right side value passed to the combined comparison operator can be nil
        # Nil is an acceptable value (the comparison returns nil), so supressing the warning with T.unsafe
        index_diff = CLOUD_ORDER.index(cloud_a.downcase) <=> T.unsafe(CLOUD_ORDER.index(cloud_b.downcase))
        if index_diff.nil?
          CLOUD_ORDER.index(cloud_a.downcase).nil? ? 1 : -1
        else
          index_diff
        end
      end
    end
  end
end
