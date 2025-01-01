# typed: true
# frozen_string_literal: true

class GistStar < ApplicationRecord::Domain::Gists
  include Starlike

  self.table_name = :starred_gists

  belongs_to :user
  belongs_to :gist

  after_commit :instrument_create, on: :create # keep before `modify_gist_stargazer_count` callback
  after_commit :instrument_destroy, on: :destroy # keep before `modify_gist_stargazer_count` callback
  after_commit :modify_gist_stargazer_count, on: [:create, :destroy]

  scope :recently_starred_gists, -> { joins(:gist).merge(Gist.public_listing).order("starred_gists.created_at DESC") }
  scope :filter_spam_for, ->(viewer) do
    return scoped if !GitHub.spamminess_check_enabled? || viewer.try(:site_admin?)

    user_ids = scoped.pluck(:user_id)
    non_spammy_user_ids = User.where(id: user_ids).filter_spam_for(viewer).pluck(:id)
    scoped.where(user_id: non_spammy_user_ids)
  end

  private

  def modify_gist_stargazer_count
    return unless gist

    change_count = !GitHub.spamminess_check_enabled? || (user && !user&.spammy?)
    return unless change_count

    gist&.touch
  end

  def instrument_create
    # Hydro
    GlobalInstrumenter.instrument("user.star",
      hydro_attributes_for(entity: gist, actor: actor, context: hydro_context_type))
  end

  def instrument_destroy
    # Hydro
    GlobalInstrumenter.instrument("user.unstar",
      hydro_attributes_for(entity: gist, actor: actor, context: hydro_context_type))
  end
end
