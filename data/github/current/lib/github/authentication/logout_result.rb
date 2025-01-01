# typed: true
# frozen_string_literal: true

class GitHub::Authentication::LogoutResult

  # A key for storing in flash for code to hook into after logout occurs.
  # See clear-data-on-logout.ts
  SUCCESS_KEY = "logout-was-successful"

  # Whether logout was successful. Most authentication adaptors will always
  # succeed, but external authentication may have custom definitions.
  attr_accessor :success

  # Options for where we should redirect to after a logout attempt. Used
  # regardless of whether logout was successful. See
  # ActionController::Base#redirect_to.
  attr_accessor :redirect_to, :flash

  def self.success(path_or_url, flash = {})
    new({
      success: true,
      redirect_to: path_or_url,
      flash: flash
    })
  end

  def self.failure(path_or_url, flash = {})
    new({
      success: false,
      redirect_to: path_or_url,
      flash: flash,
    })
  end

  def initialize(options = {})
    options.each do |k, v|
      ivar = "@#{k}".to_sym
      instance_variable_set ivar, v
    end
  end

  def success?
    success
  end

  def failure?
    !success?
  end
end
