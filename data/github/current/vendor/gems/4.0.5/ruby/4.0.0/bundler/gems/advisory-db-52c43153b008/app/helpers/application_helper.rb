# frozen_string_literal: true

require "redcarpet"

module ApplicationHelper
  def test_selector(value, name: nil)
    return if Rails.env.production?

    "#{test_selector_attr(name)}=#{value}"
  end

  def test_selector_data_hash(value, name: nil)
    return {} if Rails.env.production?

    { test_selector_attr(name) => value }
  end

  def test_selector_attr(name)
    name ? "data-test-selector-#{name}" : "data-test-selector"
  end

  def markdown(text)
    renderer = Redcarpet::Render::HTML.new(prettify: true)
    markdown = Redcarpet::Markdown.new(renderer, fenced_code_blocks: true)
    sanitize(markdown.render(text), tags: %w[p br strong em ul ol li blockquote h1 h2 h3 h4 h5 h6 pre code a], attributes: %w[href title])
  end
end
