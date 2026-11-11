# typed: true
# frozen_string_literal: true

class FollowsValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return unless value.present?

    prior = record[options[:with]] || Time.now

    if value <= prior
      record.errors.add attribute, "must be after #{options[:with]}"
    end
  end
end
