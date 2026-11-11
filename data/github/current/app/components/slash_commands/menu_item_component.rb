# typed: true
# frozen_string_literal: true

class SlashCommands::MenuItemComponent < ApplicationComponent
  attr_reader :id, :title, :description, :url, :test_selector_id, :hidden_fields, :group_id

  def initialize(title:, url:, description: nil, id: nil, test_selector_id: "menu-item", group_id: nil, hidden_fields: {})
    @id = id
    @title = title
    @description = description
    @url = url
    @test_selector_id = test_selector_id
    @hidden_fields = hidden_fields
    @group_id = group_id
  end

  def has_group?
    group_id.present?
  end
end
