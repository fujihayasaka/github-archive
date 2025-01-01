# typed: true
# frozen_string_literal: true

# This base controller is intended for use with memex sub-controllers
# e.g. memex views, columns, etc.
class Memexes::Controller < ApplicationController
  include MemexesHelper
  include ApplicationController::JsonDependency
  include GitHub::Memoizer

  before_action :require_memex_feature_enabled
  before_action :parse_json_params

  # Safe because :require_memex_feature_enabled requires memex_owner, which requires this_memex
  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless this_memex # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    this_memex
  end

  # Safe because :require_memex_feature_enabled requires memex_owner, which requires this_memex
  def target_for_conditional_access
    target = this_memex&.target_for_conditional_access
    return :no_target_for_conditional_access unless target # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    target
  end

  memoize def this_memex
    find_readable_memex
  end

  def memex_owner
    this_memex&.owner
  end

  def find_readable_memex
    if params[:memex_id].present?
      # restful memex id scoped route
      project = MemexProject.find_by(id: params[:memex_id])
      return nil if project.nil? || project.deleted?
      project
    elsif params[:org].present? && params[:memex_number].present?
      # legacy org scoped route
      org = Organization.find_by_login(params[:org])
      return nil unless org.present?
      org.memex_projects.active_projects.includes(:owner).find_by(number: params[:memex_number])
    end
  end

  def require_memex_feature_enabled
    return false unless memex_owner
    render_404 unless GitHub.projects_new_enabled?
  end

  def initialize_hydro_context
    super

    if hydro_context && hydro_context[:enabled] && memex_owner.is_a?(Organization)
      hydro_context.merge!({
        current_org: memex_owner.name,
        current_org_id: memex_owner.id,
      })
    end
  end
end
