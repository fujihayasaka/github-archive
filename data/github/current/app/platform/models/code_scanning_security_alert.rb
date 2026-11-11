# typed: true
# frozen_string_literal: true

class Platform::Models::CodeScanningSecurityAlert

  attr_reader :number, :title, :status

  def initialize(number, title, status, repository_id)
    @number = number
    @title = title
    @status = status
    @repository_id = repository_id
  end

  def async_repository
    return @async_repository if defined?(@async_repository)

    @async_repository = Platform::Loaders::ActiveRecord.load(::Repository, @repository_id)
  end

  def async_viewable?(viewer)
    async_repository.then do |repository|
      repository.async_code_scanning_allowed?(:read_code_scanning, viewer)
    end
  end
end
