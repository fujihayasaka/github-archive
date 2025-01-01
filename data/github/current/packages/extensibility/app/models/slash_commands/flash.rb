# typed: true
# frozen_string_literal: true

module SlashCommands
  class Flash
    attr_accessor :info, :notice, :error

    def present?
      info.present? || notice.present? || error.present?
    end
  end
end
