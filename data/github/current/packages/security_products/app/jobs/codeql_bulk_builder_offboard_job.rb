# typed: true
# frozen_string_literal: true

# CodeqlBulkBuilderOffboardJob offboards repositories from CodeQL database bulk building.
# See also: CodeqlBulkBuilderConfig and CodeqlDatabaseBulkBuilderJob
class CodeqlBulkBuilderOffboardJob < ApplicationJob
  queue_as :code_scanning_multi_repository_variant_analysis
  retry_on_dirty_exit

  # repos_and_languages - Array of [repo_id, language] pairs to offboard
  def perform(repos_and_languages:)
    return if GitHub.enterprise?

    CodeqlBulkBuilderConfig.throttle_writes do
      repos_and_languages.each_slice(500) do |slice|
        CodeqlBulkBuilderConfig.repos_and_languages(slice).delete_all
      end
    end
  end
end
