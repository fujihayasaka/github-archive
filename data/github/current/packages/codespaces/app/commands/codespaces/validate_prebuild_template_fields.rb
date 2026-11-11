# typed: true
# frozen_string_literal: true

module Codespaces
  class ValidatePrebuildTemplateFields < Command
    include ActiveModel::Validations

    validates_with Codespaces::LegacyPrebuildTemplateValidator


    class InvalidPrebuildTemplate < Codespaces::CreatePrebuildTemplate::Error; end

    attr_accessor :repository,
                  :location,
                  :vscs_target,
                  :vscs_target_url,
                  :oid,
                  :branch


    def initialize(
        repository:,
        vscs_target:,
        vscs_target_url:,
        location:,
        oid:,
        branch:
      )
      @repository = repository
      @location = location
      @vscs_target = vscs_target
      @vscs_target_url = vscs_target_url
      @oid = oid
      @branch = branch
    end

    def perform
      unless valid?
        raise InvalidPrebuildTemplate, "Invalid prebuild template: #{errors.full_messages.join(', ')}"
      end
    end
  end
end
