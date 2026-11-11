# frozen_string_literal: true

module UpdateConfigsService
  module V1
    class UpdateJobErrorSerializer < ErrorSerializer
      attributes :git_dependencies_not_reachable_error

      def git_dependencies_not_reachable_error
        return nil unless type == "git_dependencies_not_reachable"

        {
          urls: object.error_details["dependency-urls"],
        }
      end
    end
  end
end
