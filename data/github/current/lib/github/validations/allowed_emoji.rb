# typed: true
# frozen_string_literal: true

module GitHub
  module Validations
    # Public: Rails validation that ensures that a field, if non-nil, contains
    # exactly one permitted emoji. Native or colon-style (`:smile:`) emoji are
    # accepted.
    #
    # If you wish to disallow a different set of emoji, define a `blocked_#{attribute}?`
    # method that takes an emoji as a parameter and returns a Boolean.
    class AllowedEmojiValidator < ActiveModel::EachValidator
      # Necessary for use with the Suggester and PrefillAssociations.

      BLOCKED_CUSTOM_EMOJI = %w(basecamp basecampy feelsgood finnadie goberserk
        godmode hurtrealbad neckbeard rage1 rage2 rage3 rage4 suspect trollface).freeze
      BLOCKED_NATIVE_EMOJI = %w(eggplant frog).freeze

      def validate_each(record, attribute, value)
        return unless value
        is_blocked_method = :"blocked_#{attribute}?"
        is_blocked = if record.respond_to?(is_blocked_method)
          record.send(is_blocked_method, value)
        else
          self.class.blocked_emoji?(value)
        end

        if is_blocked
          record.errors.add(attribute, "contains an emoji that is not allowed")
        end
      end

      def self.blocked_emoji?(value)
        BLOCKED_NATIVE_EMOJI.each do |name|
          emoji_char = ::Emoji.find_by_alias(name)
          return true if emoji_char && value == emoji_char.raw
        end

        (BLOCKED_NATIVE_EMOJI + BLOCKED_CUSTOM_EMOJI).any? do |name|
          value == ":#{name}:"
        end
      end
    end
  end
end
