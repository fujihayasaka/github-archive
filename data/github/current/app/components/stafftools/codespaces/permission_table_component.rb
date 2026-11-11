# typed: true
# frozen_string_literal: true

class Stafftools::Codespaces::PermissionTableComponent < ApplicationComponent
  attr_accessor :permission_exception_types

  def initialize(codespace_id:)
    @codespace_id = codespace_id
    @resource_permissions = []
    @permission_exception_types = Set.new

    @installation = Codespace.active_installations_for([@codespace_id]).last

    if @installation&.fallback_to_permissions?
      get_permissions(@installation)
    end
  end

  def get_permissions(installation)
    permissions = Permission.where(actor: installation).sort_by(&:subject_id)
    permissions.each do |permission|
      begin
        hsh = {
          "subject_type" => permission.subject_type,
          "action" => permission.action
        }
        resource = permission.subject
        unless resource.nil?
          hsh["type"] = resource.parent.class.to_s
          hsh["resource_parent"] = resource.parent
        end
      rescue NoMethodError => exception
        @permission_exception_types << permission.subject_type
      ensure
        @resource_permissions.push(hsh)
      end
    end
  end

  def render?
    @installation.present?
  end
end
