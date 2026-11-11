# typed: true
# frozen_string_literal: true

class StrictHostValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    uri = Addressable::URI.parse(value)
    if uri.blank?
      record.errors.add(attribute, "invalid format")
    end

    unless uri&.scheme == "https"
      record.errors.add(attribute, "must use https scheme")
    end

    if uri&.query.present?
      record.errors.add(attribute, "can't have query string")
    end

    if uri&.path.present?
      record.errors.add(attribute, "can't have a path")
    end

    unless UrlHelper.valid_host?(uri&.host)
      record.errors.add(attribute, "must contain only the host")
    end
  rescue Addressable::URI::InvalidURIError => e
    record.errors.add(attribute, e.message)
  end
end
