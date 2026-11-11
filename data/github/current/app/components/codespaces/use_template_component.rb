# typed: true
# frozen_string_literal: true

class Codespaces::UseTemplateComponent < ApplicationComponent
  include AvatarHelper
  include HydroHelper

  attr_reader :template

  renders_one :form_content

  def initialize(template:, repository_policy: nil)
    @template = template
    @repository_policy = repository_policy
  end

  def creations_should_be_disabled?
    # This is a bit of a short-cut for now as there are other things we should probably be checking BUT this is the
    # most important one and is the fastest since we have to create this and run this per template repository. This
    # should ideally be using `can_attempt_create?` instead but there's unlikely to be any meaningful variance
    # in that and we can look at that later.
    !repository_policy.can_bill?
  end

  def disabled_button_reason
    "You cannot create this codespace"
  end

  def click_tracking_attributes
    payload = {
      ref: template.default_branch,
      repository_id: template.repository.id,
      target: "USE_TEMPLATE",
      user_id: current_user.id
    }
    hydro_click_tracking_attributes("codespace_create.click", payload)
  end

  private

  memoize def repository_policy
    @repository_policy || Codespaces::RepositoryPolicy.async_with_prefill(current_user, template.repository).sync
  end
end
