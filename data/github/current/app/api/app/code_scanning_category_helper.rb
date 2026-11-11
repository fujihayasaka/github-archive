# typed: true
# frozen_string_literal: true

module Api::App::CodeScanningCategoryHelper
  def compute_category(analysis_key, matrix_vars)
    category = "#{analysis_key}"

    begin
      environment = JSON.parse(matrix_vars)
    rescue JSON::ParserError
      return category
    end

    if environment.present? && environment.is_a?(Hash)
      # the id has to be deterministic so we sort the fields
      environment.keys.sort.each do |key|
        if environment[key].instance_of? String
          category += "/#{key}:#{environment[key]}"
        else
          # In code scanning we just handle the string values,
          # the rest get converted to the empty string
          category += "/#{key}:"
        end
      end
    end

    category
  end
end
