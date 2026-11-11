# typed: true
# frozen_string_literal: true

module TagAttributeHelper
  include EscapeHelper

  # Convert a Hash to HTML tag attributes.
  #
  # hash - A Hash of options.
  #
  # Returns an html_safe String of key="value" pairs.
  def tag_attributes(hash)
    parts = hash.map do |key, value|
      safe_join([
        sanitize_key(key),
        "=",
        GitHub::HTMLSafeString::DOUBLE_QUOTE,
        value,
        GitHub::HTMLSafeString::DOUBLE_QUOTE,
      ])
    end

    safe_join(parts, " ")
  end

  private

  # https://html.spec.whatwg.org/multipage/syntax.html#attributes-2
  INVALID_ATTRIBUTE_CHARACTERS = [
    "\u0020", # SPACE
    "\u0009", # CHARACTER TABULATION (tab)
    "\u000A", # LINE FEED (LF)
    "\u000C", # FORM FEED (FF)
    "\u000D", # CARRIAGE RETURN (CR)
    "\u0000", # NULL
    "\u0022", # QUOTATION MARK (")
    "\u0027", # APOSTROPHE (')
    "\u003E", # GREATER-THAN SIGN (>)
    "\u002F", # SOLIDUS (/)
    "\u003D", # EQUALS SIGN (=)
    "\u0000", # NULL
    "\u0001", # START OF HEADING
    "\u0002", # START OF TEXT
    "\u0003", # END OF TEXT
    "\u0004", # END OF TRANSMISSION
    "\u0005", # ENQUIRY
    "\u0006", # ACKNOWLEDGE
    "\u0007", # BELL
    "\u0008", # BACKSPACE
    "\u0009", # CHARACTER TABULATION
    "\u000A", # LINE FEED (LF)
    "\u000B", # LINE TABULATION
    "\u000C", # FORM FEED (FF)
    "\u000D", # CARRIAGE RETURN (CR)
    "\u000E", # SHIFT OUT
    "\u000F", # SHIFT IN
    "\u0010", # DATA LINK ESCAPE
    "\u0011", # DEVICE CONTROL ONE
    "\u0012", # DEVICE CONTROL TWO
    "\u0013", # DEVICE CONTROL THREE
    "\u0014", # DEVICE CONTROL FOUR
    "\u0015", # NEGATIVE ACKNOWLEDGE
    "\u0016", # SYNCHRONOUS IDLE
    "\u0017", # END OF TRANSMISSION BLOCK
    "\u0018", # CANCEL
    "\u0019", # END OF MEDIUM
    "\u001A", # SUBSTITUTE
    "\u001B", # ESCAPE
    "\u001C", # INFORMATION SEPARATOR FOUR
    "\u001D", # INFORMATION SEPARATOR THREE
    "\u001E", # INFORMATION SEPARATOR TWO
    "\u001F", # INFORMATION SEPARATOR ONE
    "\u007F", # DELETE
    "\u0080", #
    "\u0081", #
    "\u0082", # BREAK PERMITTED HERE
    "\u0083", # NO BREAK HERE
    "\u0084", #
    "\u0085", # NEXT LINE (NEL)
    "\u0086", # START OF SELECTED AREA
    "\u0087", # END OF SELECTED AREA
    "\u0088", # CHARACTER TABULATION SET
    "\u0089", # CHARACTER TABULATION WITH JUSTIFICATION
    "\u008A", # LINE TABULATION SET
    "\u008B", # PARTIAL LINE FORWARD
    "\u008C", # PARTIAL LINE BACKWARD
    "\u008D", # REVERSE LINE FEED
    "\u008E", # SINGLE SHIFT TWO
    "\u008F", # SINGLE SHIFT THREE
    "\u0090", # DEVICE CONTROL STRING
    "\u0091", # PRIVATE USE ONE
    "\u0092", # PRIVATE USE TWO
    "\u0093", # SET TRANSMIT STATE
    "\u0094", # CANCEL CHARACTER
    "\u0095", # MESSAGE WAITING
    "\u0096", # START OF GUARDED AREA
    "\u0097", # END OF GUARDED AREA
    "\u0098", # START OF STRING
    "\u0099", #
    "\u009A", # SINGLE CHARACTER INTRODUCER
    "\u009B", # CONTROL SEQUENCE INTRODUCER
    "\u009C", # STRING TERMINATOR
    "\u009D", # OPERATING SYSTEM COMMAND
    "\u009E", # PRIVACY MESSAGE
    "\u009F", # APPLICATION PROGRAM COMMAND
  ].join

  # Remove invalid characters from the argument name.
  #
  # key - A String.
  #
  # Returns a String.
  def sanitize_key(key)
    key.to_s.tr(INVALID_ATTRIBUTE_CHARACTERS, "")
  end
end
