# typed: true
# frozen_string_literal: true

class Page::CustomSubdomain
  def initialize(database_value, shortcode)
    @database_value = database_value
    @routable_value = @database_value.chomp("_#{shortcode}")
  end

  def validate
    validate_length
    validate_format
    validate_uniqueness
    true
  end

  def validate_length
    if @routable_value.length > 63
      raise Page::InvalidCustomSubdomain, "The custom subdomain cannot exceed 63 characters."
    end
  end

  def validate_format
    reg = /\A[a-z0-9](([a-z0-9\-])*[a-z0-9])?\Z/

    unless reg.match?(@routable_value)
      message = "The custom subdomain can only contain lowercase alphanumeric characters and dashes and cannot begin or end with a dash."
      raise Page::InvalidCustomSubdomain, message
    end
  end

  def validate_uniqueness
    unless Page.where(custom_subdomain: @database_value).empty?
      raise Page::InvalidCustomSubdomain, "Custom subdomain is already in use."
    end
    unless Page.where(subdomain: @database_value).empty?
      raise Page::InvalidCustomSubdomain, "Custom subdomain is already in use."
    end
  end
end
