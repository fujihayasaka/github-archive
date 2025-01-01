# typed: true
# frozen_string_literal: true
module GitHub::Goomba
  class EmailReplyFilter < InputFilter
    def self.cache_key(context)
      HTML::Pipeline::EmailReplyFilter.cache_key(context)
    end

    def call(string)
      HTML::Pipeline::EmailReplyFilter.new(string, context).call
    end
  end
end
