# frozen_string_literal: true

module CWEs
  class LinkedCWERowComponent < ApplicationComponent
    attr_reader :name_prefix, :cwe_id, :cwe_name

    def initialize(name_prefix:, cwe_id: nil, cwe_name: "{{ cwe_name }}", disabled: false)
      @name_prefix = name_prefix
      @visible = !cwe_id.nil?
      @cwe_id = cwe_id || "{{ cwe_id }}"
      @cwe_name = cwe_name
      @disabled = disabled
    end

    def visible?
      @visible
    end

    def unknown?
      cwe_name.nil?
    end
  end
end
