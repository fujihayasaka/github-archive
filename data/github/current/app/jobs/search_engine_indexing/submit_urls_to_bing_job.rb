# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

require "bing/url_submission_client"

module SearchEngineIndexing
  class SubmitUrlsToBingJob < ApplicationJob
    retry_on_dirty_exit

    queue_as :search_engine_indexing

    rescue_from(Faraday::Error) do |exception|
      GitHub.logger.warn(
        "Error returned when submitting URLs to Bing",
        "#{self.class.name}" => exception.message
      )
    end

    def perform(urls)
      with_read { bing_client.submit(urls) }
    end

    private

    def bing_client
      @bing_client ||= Bing::UrlSubmissionClient.new
    end
  end
end
