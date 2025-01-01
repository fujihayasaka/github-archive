# typed: true
# frozen_string_literal: true

class Codespaces::AllowPermissionsRowItemComponent < ApplicationComponent

  attr_reader :label, :permissions, :icon, :color, :action, :is_prebuild

  def initialize(label:, permissions:, icon:, color: "", action: "requested", is_prebuild: false)
    @label = label
    @permissions = build_permissions_for_view(permissions)
    @icon = icon
    @color = color
    @action = action
    @is_prebuild = is_prebuild
  end

  private

  def build_permissions_for_view(permissions)
    view_permissions = {}
    rows = permissions.map do |resource, action|
      view_permissions[Resource.new(resource)] = action
    end
    # put mandatory resources at the top
    view_permissions.sort_by { |resource, _| resource.mandatory? ? 0 : 1 }.to_h
  end

  class Resource
    def initialize(resource)
      @resource = resource
    end

    def to_s
      @resource
    end

    def titleize
      @resource.titleize
    end

    def mandatory?
      Codespaces::DevContainerConfig::Codespaces::MANDATORY_PERMISSIONS.include?(@resource)
    end
  end
end
