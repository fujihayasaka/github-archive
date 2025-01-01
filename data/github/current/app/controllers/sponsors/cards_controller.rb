# typed: strict
# frozen_string_literal: true

class Sponsors::CardsController < ApplicationController
  include Sponsors::Embeddable

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:show]

  sig { void }
  def show
    render "sponsors/card/show", locals: {
      sponsorable: sponsorable,
      sponsors_listing: sponsorable_sponsors_listing,
    }, layout: "layouts/sponsors/embed"
  end
end
