# frozen_string_literal: true

require "renderer"

module Middlewares
  class CheckParams < Coach::Middleware
    def call
      params_to_check.each do |param|
        return param_missing_error(param) if param_missing_but_required?(param)
        return param_type_error(param) if param_type_mismatch?(param)
      end

      next_middleware.call
    rescue ActionDispatch::Http::Parameters::ParseError
      invalid_json_error
    end

    private

    def params_to_check
      config.keys
    end

    def param_requirements(param)
      config[param]
    end

    def param_missing_but_required?(param_name)
      name_path = param_name.to_s.split(".").map(&:to_sym)
      param_requirements(param_name)[:required] && params.dig(*name_path).nil?
    end

    def param_missing_error(param)
      Renderer.render_error(
        status: 400,
        title: "Bad Request",
        detail: "Missing required parameter: #{param}",
      )
    end

    def invalid_json_error
      Renderer.render_error(
        status: 400,
        title: "Bad Request",
        detail: "Invalid JSON",
      )
    end

    def param_type_mismatch?(param_name) # rubocop:disable Metrics/PerceivedComplexity
      name_path = param_name.to_s.split(".").map(&:to_sym)
      return false unless param_requirements(param_name)[:type]

      if name_path.count > 1
        return false unless params.dig(*name_path[0..-2])&.key?(name_path.last)
      else
        return false unless params.key?(name_path.last)
      end

      Array[*param_requirements(param_name)[:type]].none? do |type|
        params.dig(*name_path).is_a?(type)
      end
    end

    def param_type_error(param)
      name_path = param.to_s.split(".").map(&:to_sym)
      type = params.dig(*name_path).class

      Renderer.render_error(
        status: 400,
        title: "Bad Request",
        detail: "Parameter '#{param}' is of type #{type} but " \
                "should be of type #{param_requirements(param)[:type]}",
      )
    end
  end
end
