# typed: strict
# frozen_string_literal: true

# Helper module for processing client-side attestation query strings:
# - Ensures browser URLs follow GitHub-standard syntax while producing parameters that TMA can process
# - Helps transform parameters like "predicate-type:sbom sort:created-desc" into structured parameters (predicate_type=sbom&direction=2)
# - Handles special values like date macros (@today) that the API doesn't support directly
module TrustMetadata
  class AttestationsQueryHelper
    # Define known parameter keys to distinguish them from subject names, which can be searched via free-form text
    KNOWN_PARAMS = %w[sort predicate-type created].freeze

    ASC_SORT_DIR = 1
    DESC_SORT_DIR = 2

    sig { params(date_macro_helper: T.untyped).void }
    def initialize(date_macro_helper)
      @date_macro_helper = date_macro_helper
    end

    sig { params(params: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
    def process_query_params(params)
      processed_params = {}
      return processed_params unless params[:q].present?

      query = params[:q]

      query = process_date_tokens(query, params)
      query = extract_known_parameters(query, processed_params)

      # The filter input box allows users to enter free-form text to search for a subject name, which is not tied to a specific parameter in the query string.
      # Since subject name is treated as free-form text rather than a structured parameter, it is not included in the list of known parameters.
      processed_params[:subject_name] = query.strip if query.strip.present?

      copy_pagination_params(params, processed_params)

      processed_params
    end

    # Processes known parameter keys and extracts their values
    sig { params(query: String, processed_params: T::Hash[Symbol, T.untyped]).returns(String) }
    private def extract_known_parameters(query, processed_params)
      KNOWN_PARAMS.each do |param|
        param_match = query.match(/\b#{Regexp.escape(param)}:([^\s]+)\b/)
        if param_match
          if param == "sort"
            # Handle sort parameter specifically
            direction = param_match[1] == "created-asc" ? ASC_SORT_DIR : DESC_SORT_DIR
            processed_params[:direction] = direction
          else
            # Handle other parameters
            key_name = param.gsub("-", "_").to_sym
            processed_params[key_name] = param_match[1]
          end
          query = query.gsub(/\b#{Regexp.escape(param)}:[^\s]+\b/, "").strip
        end
      end
      query
    end

    # Copies other parameters (before, after, per_page) from source to target params
    sig { params(source_params: T.untyped, target_params: T::Hash[Symbol, T.untyped]).void }
    private def copy_pagination_params(source_params, target_params)
      [:before, :after, :per_page].each do |param|
        target_params[param] = source_params[param] if source_params[param].present?
      end
    end

    sig { params(query: T.nilable(String), params: T.untyped).returns(String) }
    def process_date_tokens(query, params)
      return query || "" unless query.present?

      # Process tokens like "created:@today" -> "created:=2025-04-18"
      processed_query = query.gsub(/([a-z_-]+):(@today[+-]?\d*[dwmy]?)/) do
        field = $1
        date_value = @date_macro_helper.replace_today_macro($2, timezone: "UTC")
        # Add = prefix if no operator exists
        if !date_value.start_with?("=", ">", "<", "<=", ">=")
          "#{field}:=#{date_value}"
        else
          "#{field}:#{date_value}"
        end
      end

      # Handle ">@today" tokens (e.g., "created:>@today-1w" -> "created:>2024-04-10")
      processed_query = processed_query.gsub(/([a-z_-]+):([><]=?)(@today[+-]\d+[dwmy]?)/) do
        field = $1
        operator = $2
        date_value = @date_macro_helper.replace_today_macro($3, timezone: "UTC")
        "#{field}:#{operator}#{date_value}"
      end

      # Handle direct date values without operator (e.g., "created:2025-05-29" -> "created:=2025-05-29")
      processed_query = processed_query.gsub(/([a-z_-]+):(\d{4}-\d{2}-\d{2})/) do
        field = $1
        date = $2
        "#{field}:=#{date}"
      end

      processed_query
    end
  end
end
