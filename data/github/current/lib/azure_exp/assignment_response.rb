# typed: true
# frozen_string_literal: true

require "json"

module AzureEXP
  # Parses an assignment response from Azure and exposees the assignment context and condig data.
  # see: https://expdocs.azurewebsites.net/docs/assignment/makeasamplecall.html
  class AssignmentResponse

    attr_reader :body

    def initialize(body)
      @body = to_h(body)
    end

    def assignment_context
      @body["AssignmentContext"]
    end

    # Returns a hash of variants or an empty hash
    # example: {"button_color":"button-red"}
    def variants_by_namespace(namespace = "default")
      return {} if @body["Configs"].nil?
      @configs ||= @body["Configs"].each do |config|
        return config["Parameters"] if config["Id"] == namespace
      end
      {}
    end

    def namespaces
      return [] if @body["Configs"].nil?
      @body["Configs"].map { |config| config["Id"] }
    end

    private

    def to_h(body)
      return {} if body.nil? || body.empty?
      body = JSON.parse(body)
    end
  end
end
