# typed: strict
# frozen_string_literal: true

class ScopedIntegrationInstallation::Result

  class Error < StandardError; end

  sig do
    params(
      installation: T.any(ScopedIntegrationInstallation, SiteScopedIntegrationInstallation),
      found_cached: T::Boolean
    ).returns(T.attached_class)
  end
  def self.success(installation, found_cached: false)
    new(:success, installation: installation, found_cached: found_cached)
  end

  sig { params(error: String).returns(T.attached_class) }
  def self.failed(error) = new(:failed, error: error)

  sig { returns(T.nilable(String)) }
  attr_reader :error

  sig { returns(T.nilable(T.any(ScopedIntegrationInstallation, SiteScopedIntegrationInstallation))) }
  attr_reader :installation

  sig { returns(T.nilable(String)) }
  attr_accessor :credential

  sig do
    params(
      status: Symbol,
      installation: T.nilable(T.any(ScopedIntegrationInstallation, SiteScopedIntegrationInstallation)),
      error: T.nilable(String),
      found_cached: T::Boolean
    ).void
  end
  def initialize(status, installation: nil, error: nil, found_cached: false)
    @status       = status
    @installation = installation
    @error        = error
    @found_cached = found_cached
  end

  sig { returns(T::Boolean) }
  def success?
    @status == :success
  end

  sig { returns(T::Boolean) }
  def failed?
    @status == :failed
  end

  sig { returns(T::Boolean) }
  def found_cached?
    @found_cached
  end
end
