# typed: strict
# frozen_string_literal: true

class DisableAdvancedTrackingJob < ApplicationJob
  queue_as :code_scanning

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  locked_by timeout: 15.minutes, key: ->(job) {
    args, = job.arguments
    "disable-advanced-tracking-#{args[:repository_id]}"
  }

  sig { params(ref: String, repository_id: Integer).void }
  def perform(ref:, repository_id:)
    return if ref.blank?

    repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      Repositories.domain.by_id(repository_id)
    else
      Repository.find_by(id: repository_id)
    end
    return if repo.nil?

    response = GitHub::Turboscan.get_tool_status(
      repository_id: repo.id,
      ref: ref,
    )

    if response.nil? || response.data.nil? || response.error.present?
      GitHub.logger.error("No response when fetching tool status from Turboscan",
        error: response&.error,
        "gh.repo.id": repo.id,
        "gh.git.ref": ref,
      )
      return
    end

    tools = response.data.tools

    codeql_tools = tools.select { |tool| tool.name.include?("CodeQL") }

    # Check if any of the categories have a delivery origin of YML or API. If not,
    # either there are no CodeQL advanced setup configurations or they are all
    # outdated. Either way, we should disable advanced tracking.
    return if codeql_tools.any? do |tool|
      tool.categories.any? { |category| [:DELIVERY_ORIGIN_YML, :DELIVERY_ORIGIN_API].include?(category.configuration_group&.delivery_origin) }
    end

    GitHub::Turboscan.set_advanced_setup_requested(repository_id: repo.id, advanced_setup_requested: false)
    GitHub.logger.info("No CodeQL tools found with YML/API delivery origin, disabling advanced tracking",
      "gh.repo.id": repo.id,
      "gh.git.ref": ref,
    )
  end
end
