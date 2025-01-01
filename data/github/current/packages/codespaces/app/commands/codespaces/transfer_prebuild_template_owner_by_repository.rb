# typed: true
# frozen_string_literal: true

module Codespaces

  class TransferPrebuildTemplateOwnerByRepository < Command

    attr_reader :repository

    def initialize(repository:)
      @repository = repository
    end

    def perform
      PrebuildTemplate.where(repository: repository).select(:id, :guid).find_each do |template|
        TransferPrebuildTemplateBillableOwner.call(template.guid)
      end
    end

  end

end
