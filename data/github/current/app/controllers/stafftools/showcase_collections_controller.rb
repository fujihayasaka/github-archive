# typed: true
# frozen_string_literal: true

# stafftools for showcase crud
class Stafftools::ShowcaseCollectionsController < StafftoolsController
  include ShowcaseCollectionsControllerMethods

  before_action :showcase_disabled
  before_action :find_collection, except: [:index, :new, :create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:index]

  def index
    redirect_to stafftools_explore_path
  end

  def show
    render "stafftools/showcase_collections/show", locals: {
      showcase: @collection,
    }
  end

  def new
    new_collection(:stafftools)
  end

  def create
    create_collection(:stafftools)
  end

  def edit
    edit_collection(:stafftools)
  end

  def update
    update_collection(:stafftools)
  end

  def destroy
    destroy_collection(:stafftools)
  end
end
