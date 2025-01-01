require "dependency_graph/sbom/spdx/generator"

module RepositorySBOMService
  module V1
    class Handler
      attr_reader :spdx_generator

      def initialize(spdx_generator: DependencyGraph::SBOM::SPDX::Generator.new)
        @spdx_generator = spdx_generator
      end

      def get_repository_s_b_o_m(request, env)
        response = DependencyGraphAPI::V1::GetRepositorySBOMResponse.new

        doc = spdx_generator.generate(
          repository_id: request.repository_id,
          repository_name: request.repository_name,
          namespace_base: request.namespace_base,
          repository_license: request.repository_license
        )

        response.payload = JSON.dump(doc)
        response
      end
    end
  end
end
