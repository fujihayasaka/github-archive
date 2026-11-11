# typed: true
# frozen_string_literal: true

require "set"

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class FilterActiveWorkflows
        include Api::Internal::Twirp::Actions::Core::V1::ArgumentsDependency

        attr_reader :req, :env


        def self.call(req, env)
          new(req, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call

          if id_argument(req.repository_id).blank?
            return Twirp::Error.invalid_argument("must be valid repository_id", argument: "repository_id")
          end

          if req.workflow_paths.blank?
            return { workflow_paths: [] }
          end

          disabled_set = Set.new
          Actions::Workflow.where(repository_id: req.repository_id).disabled
            .in_batches(of: 500) do |relation|
              paths = relation.pluck(:path).map { |raw_path| raw_path.dup.force_encoding(Encoding::UTF_8) }
              disabled_set.merge(paths)
            end
          requested_workflows = req.workflow_paths.reject { |path| disabled_set.include?(path) }

          { workflow_paths: requested_workflows }
        end
      end
    end
  end
end
