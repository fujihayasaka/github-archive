# typed: true
# frozen_string_literal: true

class Memex::ProjectList::AddProjectButtonComponent < ApplicationComponent
  extend T::Sig

  sig { params(owner: T.any(Organization, User), is_template: T::Boolean, ui: T.nilable(MemexStats::UIValues)).void }
  def initialize(owner:, is_template: false, ui: nil)
    @owner = owner
    @is_template = is_template
    @ui = ui
  end

  def render?
    case @owner
    when Organization
      current_organization&.member?(current_user)
    when User
      current_user == @owner
    end
  end

  memoize def create_path
    case @owner
    when Organization
      create_org_memex_path(current_organization)
    when User
      create_user_project_beta_path(current_user, type: "new")
    end
  end
end
