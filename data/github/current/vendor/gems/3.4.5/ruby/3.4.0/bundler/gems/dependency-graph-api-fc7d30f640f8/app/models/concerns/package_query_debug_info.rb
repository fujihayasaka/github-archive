module PackageQueryDebugInfo
  extend ActiveSupport::Concern

  def self.extended(item)
    class << item
      attr_accessor :debug_should_be_associated_to_repo
      attr_accessor :debug_association_explanation
    end
  end

  def self.write_debug_info(debug_results, non_debug_filtered_data, minimum_repository_id_certainty)
    hashed_prod_data = non_debug_filtered_data.index_by(&:id)
    # We have extra debug info we will use to populate debug fields on results
    debug_results.each do |item|
      item.extend PackageQueryDebugInfo
      item.debug_should_be_associated_to_repo = hashed_prod_data.key?(item.id)

      unless item.debug_should_be_associated_to_repo == true
        if item.repository_id_certainty >= minimum_repository_id_certainty
          item.debug_association_explanation = "Matching manifest could not be found in repository."
        else
          item.debug_association_explanation = "Certainty of match did not meet the minimum needed to be associated to repo."
        end
      end
    end
  end
end
