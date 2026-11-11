# typed: true
# frozen_string_literal: true

class LinkHeader
  attr_reader :url, :options
  def initialize(url, options)
    @url, @options = url, options
  end

  def to_header
    opts   = options.dup
    params = ["<#{url}>"]
    if rel = opts.delete(:rel)
      params << "rel=#{rel.to_s.inspect}"
    end
    opts.each do |key, value|
      params << "#{key}=#{value.to_s.inspect}"
    end
    params * "; "
  end
end
