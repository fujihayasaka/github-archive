# typed: false
# frozen_string_literal: true

module Actions
  class TopNCloudCustomizer

    AZURE_CREATOR = "Microsoft Azure"
    POPULAR_CLOUD_LANGUAGES = ["Dockerfile"]
    POPULAR_CLOUD_TEMPLATES = Set["deployments/azure", "deployments/azure-webapps-node", "deployments/alibabacloud", "deployments/aws", "deployments/google", "deployments/terraform", "deployments/ibm", "deployments/openshift", "deployments/tencent"].freeze

    class << self
      # This customization adds a layer on top of descending order of templates by weight.
      # It helps represent cloud templates in the order of repo language significance.
      # The grouping follows the SQL order: language_percentage desc, cloud_display_order asc, template_weight desc
      # If any slots are left, it appends popular partner templates for those clouds that don't have any representation yet.
      def customize_templates(repo_relevant_templates, non_relevant_templates, repository:, max_num_of_templates:)
        tech_stack = WorkflowTemplateHelper::repo_tech_stacks_percent_size(repository)
        @languages_percentage = {}
        @languages_percentage = tech_stack.select { |stack, _|  stack.is_language? } if tech_stack.present?

        if repo_relevant_templates.empty? || !@languages_percentage.present?
          return get_sorted_popular_templates non_relevant_templates
        end

        @languages_percentage = tech_stack.select { |stack, _|  stack.is_language? }
        unless @languages_percentage.present?
          return get_sorted_popular_templates non_relevant_templates
        end

        languages = @languages_percentage.keys.map(&:name)
        repo_popular_tech_stack = POPULAR_CLOUD_LANGUAGES & languages
        languages = repo_popular_tech_stack + (languages - repo_popular_tech_stack) unless repo_popular_tech_stack.empty?

        customized_repo_templates = pick_cloud_templates_for_each_language(repo_relevant_templates, languages, max_num_of_templates)
        customized_repo_templates.concat(non_relevant_templates.first(max_num_of_templates - customized_repo_templates.size))
      end


      private

      def pick_cloud_templates_for_each_language(templates, languages, max_num_of_templates)

        # Group templates based on languages first and then by clouds. The DS looks like below:
        # [
        #   ["node",
        #     ["aws",
        #       [
        #         "node-aws-template-1",
        #         "node-aws-template-2"
        #       ]
        #     ]
        #   ],
        #   ["python",
        #     ["azure",
        #       [
        #         "python-azure-template-1"
        #       ]
        #     ],
        #     ["gcp",
        #       [
        #         "python-gcp-template-1",
        #         "python-gcp-template-2"
        #       ]
        #     ]
        #   ]
        # ]
        # The grouping follows the SQL order: language_percentage desc, cloud_display_order asc, template_weight desc
        # The RELEVANT templates rendered for the above DS looks like:["node-aws-template-1", "python-azure-template-1", "python-gcp-template-1", "node-aws-template-2", "python-gcp-template-2"]
        templates_by_language = languages.map do |language|
          [language, get_top_cloud_templates_for_language(language, templates, max_num_of_templates)]
        end
        templates_to_render = Set[]
        rank = 0
        any_language_cloud_max_size = 1
        # Loop through each language bucket and add one template per cloud based on ranking.
        # Keep doing that till you hit max_num_of_templates count.
        while true
          templates_by_language.each do |cloud_templates_for_language|
            #clouds array is the 2nd item in the 2-element cloud_templates_for_language array.
            cloud_templates_for_language[1].each do |cloud_templates|
              #templates array is the 2nd item in the 2-element cloud_templates array.
              any_language_cloud_max_size = [any_language_cloud_max_size, cloud_templates[1].size].max
              templates_to_render.add(cloud_templates[1][rank]) if templates_to_render.size < max_num_of_templates && cloud_templates[1].size > rank
              return templates_to_render.to_a if templates_to_render.size == max_num_of_templates
            end
          end
          # A loop on language buckets is done. Start the next one and pick next ranked templates from language clouds.
          rank += 1
          break if rank == any_language_cloud_max_size
        end

        templates_to_render.to_a
      end

      def get_top_cloud_templates_for_language(language, templates, max_num_of_templates)
        templates
          # select templates for matching language and where creator is non-empty
          .select { |template| !template.creator.nil? && !template.creator.empty? && template.matches_language?(language) }
          # group by creator (which is cloud provider name in this case)
          .group_by { |template| template.creator }
          .sort { |a, b| Actions::WorkflowTemplate::CloudComparator.new.compare_clouds(a.first, b.first) }
          # take top max_num_of_templates as we can't recommend anything beyond that
          .first(max_num_of_templates)
      end

      def get_sorted_popular_templates(non_relevant_templates)
        popular_partner_templates, residual_templates = non_relevant_templates.partition { |template| POPULAR_CLOUD_TEMPLATES.include?(template.id) }
        popular_partner_templates.sort { |a, b| Actions::WorkflowTemplate::CloudComparator.new.compare(a, b) }
      end
    end
  end
end
