# typed: true
# frozen_string_literal: true

require "set"
require "github/pi_link_header"

# Maintains the collection of Api::LinkHeader instances for an API request.
class PiLinkCollection
  attr_reader :url, :params

  PAGINATION_RELATIONS = Set.new %w(next last first prev)

  def initialize(url, params)
    @url            = url
    @params         = params
    @links          = []
    @has_pagination = false
  end

  # Public: Adds a new link relative to the current resource.  This keeps
  # any existing HTTP query parameters.
  #
  # params  - Hash of query parameters to add.
  # options - Hash of link options.
  #           :rel - The String relation of the link to the current resource.
  #
  # Returns nothing.
  def add_current(params, options = {})
    link_params = @params.dup
    params.each do |key, value|
      key_s = key.to_s
      if value.nil?
        link_params.delete(key_s)
      else
        link_params[key_s] = value
      end
    end

    add "%s?%s" % [@url, build_query(link_params)], options
  end

  # Public: Adds Link headers for pagination links for records dumped ordered
  # by ID.  We assume the last_record is taken from Array#last, and use its ID
  # to fill in the ?since parameter.
  #
  # last_record - Either an ActiveRecord object, or nil if no matches were
  #               found (and hence, no links).
  #
  # Returns nothing.
  def add_dump_pagination(last_record)
    add_current({ since: last_record.id }, rel: :next) if last_record
    add("#{@url}{?since}", rel: :first)
  end

  def has_pagination?
    @has_pagination
  end

  # Public: Checks to see if any links have been added.
  #
  # Returns true if links have been added, or false.
  def present?
    !@links.empty?
  end

  # Public: Converts the links into a single HTTP Header value.
  #
  # Returns a String.
  def to_header
    @links.map { |link| link.to_header } * ", "
  end

  # Public: Converts the links into a structure that can be converted to
  # JSON.
  #
  # Returns an Array of [String, Hash] Array tuples representing each Link.
  def to_meta
    @links.map { |link| [link.url, link.options] }
  end

  def add(url, options)
    if !@has_pagination
      rel = options[:rel].to_s
      @has_pagination = PAGINATION_RELATIONS.include?(rel)
    end

    @links << LinkHeader.new(url, options)
  end

  private

  def build_query(hash)
    require "cgi" unless defined?(CGI) && defined?(CGI::escape)
    q = []
    hash.each do |key, value|
      q << "#{CGI.escape(key.to_s)}=#{CGI.escape(value.to_s)}"
    end
    q.join("&")
  end

end
