# frozen_string_literal: true

class << GitHub::Markup
  module RenderUtf8
    def render(*args, **kwargs, &block)
      ret = super(*args, **kwargs, &block)
      if ret && !ret.valid_encoding?
        ret = GitHub::Encoding.try_guess_and_transcode(ret)
      end
      ret
    end
  end

  prepend RenderUtf8
end

class << Nokogiri::HTML::DocumentFragment
  module ParseUtf8
    def parse(str, *args)
      if str.encoding == Encoding::ASCII_8BIT || !str.valid_encoding?
        str = GitHub::Encoding.try_guess_and_transcode(str)
      end
      super(str, *args)
    end
  end

  prepend ParseUtf8
end
