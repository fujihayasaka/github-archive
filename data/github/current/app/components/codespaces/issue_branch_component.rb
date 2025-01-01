# typed: strict
# frozen_string_literal: true

class Codespaces::IssueBranchComponent < ApplicationComponent
  extend T::Sig

  include CodespacesHelper

  delegate :repository, :billable_owner, :ref, :devcontainer_path, to: :build_codespace

  sig { params(repository: ::Repository, branch_name: String).void }
  def initialize(repository:, branch_name:)
    @repository = repository
    @branch_name = branch_name
  end

  sig { returns(::Codespace) }
  memoize def build_codespace
    current_user.codespaces.new(repository: @repository, ref: @branch_name)
  end

  sig { returns(T::Boolean) }
  memoize def at_limit?
    query.at_limit?
  end

  sig { returns(Codespaces::Settings) }
  memoize def user_settings
    Codespaces::Settings.for_user(current_user)
  end

  sig { returns(Codespaces::Skus::Sku) }
  memoize def sku
    query.default_sku
  end

  sig { returns(T::Boolean) }
  memoize def machine_type_unavailable
    validator.errors.include?(:machine)
  end

  sig { returns(T::Boolean) }
  memoize def base_image_unavailable
    validator.errors.include?(:base_image)
  end

  sig { returns(String) }
  memoize def display_ref
    Git::Ref.value_for_display(ref)
  end

  private

  sig { returns(Codespaces::Query) }
  memoize def query
    Codespaces::Query.new(current_user: current_user, repository: @repository, ref: @branch_name)
  end

  sig { returns(Codespaces::Create) }
  memoize def validator
    location = Codespaces::GetRegionForUser.call(
      user: current_user,
      repository:,
    )
    # Imagine we pulled out the validations we run in Create and allowed them to be used independently here and elsewhere.
    # To do so we'd also have to make sure the errors we add to the "model" from those validations can be rendered properly
    # in e.g. the CreateNoticeFlashErrorComponent.
    Codespaces::Create.new(attributes: {
      owner: current_user,
      repository_id: repository.id,
      ref:,
      devcontainer_path:,
      location:
    }).tap(&:valid?)
  end
end
