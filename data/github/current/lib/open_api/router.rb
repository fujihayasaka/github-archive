# typed: false
# frozen_string_literal: true

module OpenApi
  class Router
    class Match
      attr_reader :path, :parameters
      attr_writer :matched_alt_path

      def initialize(description_path, parameters)
        @path             = description_path
        @parameters       = parameters
        @matched_alt_path = false
      end

      def matched_alt_path?
        @matched_alt_path
      end

      def concrete_segments
        @path.split("/") | @parameters.keys
      end
    end

    def self.match(request_path:, operation:)
      new.match(request_path: request_path, operation: operation)
    end

    def match(request_path:, operation:)
      # An exact match
      if match = find_match(request_path: request_path, operation_path: operation.path, path_parameters: operation.path_parameters)
        return match
      end

      # A match based on the main operation path with an alternative prefix
      alternative_prefixes = alternative_prefixes_for(operation.path)

      alternative_prefixes.each do |path|
        if match = find_match(request_path: request_path, operation_path: path, path_parameters: operation.path_parameters)
          match.matched_alt_path = true
          return match
        end
      end

      operation.alternative_paths.each do |alt_path|
        # A match based on any of the exact alternative paths
        if match = find_match(request_path: request_path, operation_path: alt_path, path_parameters: operation.path_parameters)
          return match
        end

        # A match based on the alternative path with an alternative prefix
        alternative_prefixes = alternative_prefixes_for(alt_path)
        alternative_prefixes.each do |path|
          if match = find_match(request_path: request_path, operation_path: path, path_parameters: operation.path_parameters)
            match.matched_alt_path = true
            return match
          end
        end
      end


      nil
    end

    protected

    def find_match(request_path:, operation_path:, path_parameters:)
      request_path_fragments     = request_path.split("/")
      description_path_fragments = operation_path.split("/")
      multi_segment_param        = extract_multi_segment_parameter(path_parameters)
      parameters                 = {}

      if multi_segment_param
        concrete_trailing_params       = []
        multisegment_param_fragments   = []
        position_of_multisegment_param = description_path_fragments.index("{#{multi_segment_param}}")
        trailing_concrete_param_amount = description_path_fragments.length - (position_of_multisegment_param + 1)

        trailing_concrete_param_amount.times do
          concrete_trailing_params << description_path_fragments.pop
          request_path_fragments.pop
        end

        return unless request_path.end_with?(concrete_trailing_params.reverse.join("/"))

        description_path_fragments.delete_at(position_of_multisegment_param)

        while request_path_fragments.length > description_path_fragments.length
          multisegment_param_fragments << request_path_fragments.pop
        end

        parameters[multi_segment_param] = multisegment_param_fragments.reverse.join("/")

        request_path_fragments += concrete_trailing_params
        description_path_fragments += concrete_trailing_params
      end


      # No match if the two paths don't have the same amount of fragments
      return if request_path_fragments.size != description_path_fragments.size

      while request_path_fragments.size > 0
        # Compare each fragment one at a time to find a match
        request_path_fragment = request_path_fragments.shift
        description_path_fragment = description_path_fragments.shift

        if templateParam = extract_template_parameter_name(description_path_fragment)
          parameters[templateParam] = request_path_fragment
        else
          if request_path_fragment != description_path_fragment
            return nil
          end
        end
      end

      Match.new(operation_path, parameters)
    end

    def extract_multi_segment_parameter(operation_parameters)
      return if operation_parameters.nil?

      operation_parameters.each do |name, param|
        return name if param.in == "path" && param.multi_segment?
      end

      nil
    end

    def extract_template_parameter_name(path_fragment)
      matches = path_fragment.match(/{(.*)}/)
      return unless matches
      matches[1]
    end

    private_constant :Match

    REPO_NAME_WITH_OWNER = %r{/repos/\{[a-z_]+\}/\{[a-z_]+\}}
    ORG_PATTERN          = %r{/orgs/\{[a-z_]+\}}
    ORG_TEAM_PATTERN     = %r{/orgs/\{[a-z_]+\}/teams/\{[a-z_]+\}}
    USER_PATTERN         = %r{/users/\{[a-z_]+\}}

    # This code is basically the reverse of the URL substitutions performed by GitHub::Routers::Api.
    # Personally, I don't have plans beyond hacking this to cover cases as I discover them.
    # This could be formalized by custom attributes in the OpenAPI schema,
    # or these routes could be given first-class specs of their own.
    #
    # @param path_pattern [String] an OpenAPI path pattern
    # @return [String, nil] An alias for `path_pattern`, if there's one that makes sense.
    def alternative_prefixes_for(path_pattern)
      alts = []

      if path_pattern.start_with?(REPO_NAME_WITH_OWNER)
        alts << path_pattern.sub(REPO_NAME_WITH_OWNER, "/repositories/{id}")
      elsif path_pattern.start_with?(ORG_TEAM_PATTERN)
        alts << path_pattern.sub(ORG_TEAM_PATTERN, "/organizations/{org_id}/team/{team_id}")
        alts << path_pattern.sub(ORG_TEAM_PATTERN, "/orgs/{org_id}/team/{team_id}")
        alts << path_pattern.sub(ORG_TEAM_PATTERN, "/organizations/{org_id}/teams/{team_id}")
      elsif path_pattern.start_with?(ORG_PATTERN)
        alts << path_pattern.sub(ORG_PATTERN, "/organizations/{id}")
      elsif path_pattern.start_with?(USER_PATTERN)
        alts << path_pattern.sub(USER_PATTERN, "/user/{id}")
      end

      alts
    end
  end
end
