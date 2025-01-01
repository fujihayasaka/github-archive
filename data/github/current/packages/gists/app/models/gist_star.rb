# typed: false
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

  private

  def modify_gist_stargazer_count
    return unless gist

    change_count = !GitHub.spamminess_check_enabled? || (user && !user.spammy?)
    return unless change_count

    gist.update_stargazer_count!
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
