# typed: true
# frozen_string_literal: true

# A simple wrapper to represent the Controller's perspective
# when updating an installation's:
# - permissions
# - repositories
# - or both
#
# Allows the controller action to focus on setting flash messages,
# redirecting and rendering.
class IntegrationInstallation
  class UpdateResult
    def self.success(installation: nil)
      new(installation, :success, nil)
    end

    def self.argument_error(message:, installation: nil)
      new(installation, :argument_error, message)
    end

    def self.input_error(message:, installation: nil)
      new(installation, :input_error, message)
    end

    def self.editor_error(message:, installation: nil)
      new(installation, :editor_error, message)
    end

    def self.permissions_error(message:, installation: nil)
      new(installation, :permissions_error, message)
    end

    def self.unknown_error(installation: nil)
      new(installation, :unknown_error, nil)
    end

    attr_reader :error, :installation, :status
    def initialize(installation, status, error)
      @installation = installation
      @status = status
      @error = error
    end

    def success?
      status == :success
    end

    def failed?
      !success?
    end
  end
end
