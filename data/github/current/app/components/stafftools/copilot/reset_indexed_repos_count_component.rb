# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::ResetIndexedReposCountComponent < ApplicationComponent
  extend T::Helpers

  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { params(copilot_user: Copilot::User).void }
  def initialize(copilot_user)
    @copilot_user = copilot_user
  end

  sig { returns(T::Boolean) }
  def show_component?
    copilot_user.has_copilot_access? && copilot_user.has_cfi_access?
  end

  sig { returns(Integer) }
  def count
    copilot_user.user_object.settings.get(:copilot_indexed_repo_count)
  end

  sig { returns(T.any(String, Integer)) }
  def quota
    CopilotIndexedRepositories::DEFAULT_COPILOT_INDIVIDUAL_INDEXING_QUOTA
  end
end
