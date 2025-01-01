# typed: true
# frozen_string_literal: true

# biztools for showcase crud
class Biztools::ShowcaseCollectionsController < BiztoolsController # rubocop:todo GitHub/ControllersShouldHaveTests
  include ShowcaseCollectionsControllerMethods

  before_action :find_collection, except: [:index, :new, :create]

  def index
    render "biztools/showcase_collections/index"
  end

  def show
    render "biztools/showcase_collections/show", locals: {
      showcase: @collection,
    }
  end

  def new
    new_collection(:biztools)
  end

  def create
    create_collection(:biztools)
  end

  def edit
    edit_collection(:biztools)
  end

  def update
    update_collection(:biztools)
  end

  def destroy
    destroy_collection(:biztools)
  end
end
