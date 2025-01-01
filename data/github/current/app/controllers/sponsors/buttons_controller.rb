# typed: strict
# frozen_string_literal: true

class Sponsors::ButtonsController < ApplicationController
  extend T::Sig
  include Sponsors::Embeddable

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:show]

  sig { void }
  def show
    render "sponsors/button/show", locals: {
      sponsorable: sponsorable,
    }, layout: "layouts/sponsors/embed"
  end
end
