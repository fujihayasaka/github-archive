# typed: false
# frozen_string_literal: true

# Extends models with the ability to calculate their own last_modified
# timestamp.
module LastModifiedCalculation
  # Public: Returns the Time that this object was last modified.
  def last_modified_at
    @last_modified_at ||= try(:updated_at) || try(:created_at) || Time.now.utc
  end

  # Calculates the last modified time for this object based on the most recent
  # timestamp based on this object's #updated_at, and any resources from the
  # attributes.
  #
  # *attrs - One or more Symbol attributes that mark dependent resources that
  #          affect the last modified timestamp for this object.
  #
  # Returns a Time.
  def last_modified_with(*attrs)
    resources = [updated_at, *attrs.map { |a| send(a) }]
    resources.flatten!
    resources.compact!
    last_modified_from(resources)
  end

  # Gets the most recent Time for the given resources:
  #
  # *resources - One or more Resources that responds to #last_modified_at, or
  #              a Time object.
  #
  # Returns a Time.
  def last_modified_from(resources)
    resources.map { |r| r.respond_to?(:last_modified_at) ? r.last_modified_at : r }.max
  end
end
