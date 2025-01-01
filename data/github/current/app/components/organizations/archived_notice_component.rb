# typed: strict
# frozen_string_literal: true

class Organizations::ArchivedNoticeComponent < ApplicationComponent
  sig { params(organization: Organization).void }
  def initialize(organization:)
    @organization = T.let(organization, Organization)
  end

  private

  delegate :feature_enabled_globally_or_for_current_user_or_entity?, to: :helpers

  sig { returns(T::Boolean) }
  def render?
    @organization.archived?
  end

  sig { returns(String) }
  def message
    "This organization was marked as archived by an administrator on #{archived_at_date}. It is no longer maintained."
  end

  sig { returns(T.nilable(String)) }
  def archived_at_date
    full_month_date @organization.archived_at
  end
end
