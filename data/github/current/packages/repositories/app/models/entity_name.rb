# typed: true
# frozen_string_literal: true

class EntityName
  INVALID_CHARACTERS_REGEX = /[^\w\.\-]+/

  attr_reader :value, :errors

  def initialize(value)
    @value = self.class.normalize(value).freeze
    @errors = []
  end

  # Public: Normalize an EntityName
  #
  # Replaces any 'non safe' characters with a dash and
  # strips off a .git extension
  #
  # Returns a String
  def self.normalize(value)
    value = value.to_s.gsub(INVALID_CHARACTERS_REGEX, "-").sub(/(\.git)+\z/i, "")
    value = value.downcase if value.end_with?(".github.com")
    value
  end

  # Public: is this EntityName valid?
  def valid?
    if @value.end_with?(".wiki")
      @errors << "cannot end in .wiki"
    end
    @errors.none?
  end

end
