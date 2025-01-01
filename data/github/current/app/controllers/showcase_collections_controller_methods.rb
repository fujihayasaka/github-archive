# typed: false
# frozen_string_literal: true

module ShowcaseCollectionsControllerMethods
  def new_collection(collection_path)
    @collection = ::Showcase::Collection.new
    case collection_path
    when :biztools
      render "biztools/showcase_collections/new", locals: { collection: @collection }
    when :stafftools
      render "stafftools/showcase_collections/new", locals: { collection: @collection }
    else
      raise NotImplementedError
    end
  end

  def create_collection(collection_path)
    owner = ::User.find(collection_hash[:owner])
    @collection = ::Showcase::Collection.new(
      owner: owner,
      name: collection_hash[:name],
      body: collection_hash[:body],
      published: collection_hash[:published],
      featured: collection_hash[:featured],
    )
    if @collection.save
      flash[:notice] = "Collection created"
      redirect_to [collection_path, @collection]
    else
      case collection_path
      when :biztools
        render "biztools/showcase_collections/new", locals: { collection: @collection }
      when :stafftools
        render "stafftools/showcase_collections/new", locals: { collection: @collection }
      else
        raise NotImplementedError
      end
    end
  end

  def set_featured
    if @collection.update_attribute(:featured, true)
      flash[:notice] = "Showcase featured"
    else
      flash[:error] = "Unable to set showcase as featured"
    end
    redirect_to :back
  end

  def remove_featured
    if @collection.update_attribute(:featured, false)
      flash[:notice] = "Showcase no longer featured"
    else
      flash[:error] = "Unable to remove featured showcase flag"
    end

    redirect_to :back
  end

  def update_collection(collection_path)
    owner = @collection.owner || ::User.find(collection_hash[:owner])
    if @collection.update(
      owner: owner,
      name: collection_hash[:name],
      body: collection_hash[:body],
      published: collection_hash[:published],
      featured: collection_hash[:featured],
    )
      flash[:notice] = "Collection updated"
      redirect_to [collection_path, @collection]
    else
      case collection_path
      when :biztools
        render "biztools/showcase_collections/edit", locals: { collection: @collection }
      when :stafftools
        render "stafftools/showcase_collections/edit", locals: { collection: @collection }
      else
        raise NotImplementedError
      end
    end
  end

  def edit_collection(collection_path)
    case collection_path
    when :biztools
      render "biztools/showcase_collections/edit", locals: { collection: @collection }
    when :stafftools
      render "stafftools/showcase_collections/edit", locals: { collection: @collection }
    else
      raise NotImplementedError
    end
  end

  def destroy_collection(collection_path)
    @collection.delete
    flash[:notice] = "Collection deleted"

    case collection_path
    when :biztools
      redirect_to biztools_showcase_collections_path
    when :stafftools
      redirect_to "/stafftools/explore"
    else
      raise NotImplementedError
    end
  end

  private

  def find_collection
    @collection = ::Showcase::Collection.find_by_slug!(params[:id])
  end

  def collection_hash
    params.require(:showcase_collection).permit(:name, :body, :published, :featured, :owner)
  end
end
