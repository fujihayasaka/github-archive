# frozen_string_literal: true

# Validates that the size in bytes of an attribute _when serialized_ is
# less than or equal to a specified maximum.
#
# In this codebase we generally make the assumption that "number of characters"
# is interchangeable with "number of bytes when encoded." Since UTF-8 is the
# default encoding, and since we're typically working with strings that contain
# only characters that fall within the ASCII range, in general one character is
# one byte and my_str.length == my_str.bytesize.
#
# However, it is entirely possible that a string may contain characters that
# fall outside of the ASCII range and may take up 2, 3, or 4 bytes when encoded.
# In these cases my_str.length < my_str.bytesize. For this reason, this
# validator operates on the _bytesize_ of the attribute when serialized for
# insertion into the database, rather than on its length.
#
class SerializedBytesizeValidator < ActiveModel::EachValidator
  def check_validity!
    raise ArgumentError, "The :maximum option is required." \
      unless options.key?(:maximum)

    raise ArgumentError, "The :maximum option must be a positive integer." \
      unless options[:maximum].is_a?(Integer) && options[:maximum].positive?
  end

  def validate_each(record, attribute, _deserialized_value)
    # NOTE: As of rails v7.1.0 we'll be able to use #read_attribute_for_database
    # instead of #attributes_for_database.
    database_attributes = record.attributes_for_database
    serialized_value = database_attributes[attribute.to_s]
    return unless serialized_value.respond_to?(:bytesize)

    maximum_bytesize = options[:maximum]
    return if serialized_value.bytesize <= maximum_bytesize

    msg = "is too long (maximum serialized size: #{maximum_bytesize} bytes, actual: #{serialized_value.bytesize})"
    record.errors.add(attribute, msg)
  end
end
