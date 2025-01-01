# frozen_string_literal: true

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
end
