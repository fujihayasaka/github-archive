# typed: false
# frozen_string_literal: true

module ShowcaseItemsControllerMethods
  def create_item(item_path)
    @repo = ::Repository.with_name_with_owner(item_hash[:name_with_owner])
    @item = @collection.items.build(item: @repo, body: item_hash[:body])

    unless @repo
      flash[:error] = "Couldn’t find repo '#{item_hash[:name_with_owner]}'"
      case item_path
      when :biztools
        render "biztools/showcase_items/edit", locals: { collection: @collection, item: @item } and return
      when :stafftools
        render "stafftools/showcase_items/edit", locals: { collection: @collection, item: @item } and return
      else
        raise NotImplementedError
      end
    end

    if @item.save
      flash[:notice] = "#{@repo.name_with_display_owner} added to #{@collection.name}"
      redirect_to [item_path, @collection]
    else
      flash[:notice] = @item.errors.full_messages.to_sentence

      case item_path
      when :biztools
        render "biztools/showcase_items/edit", locals: { collection: @collection, item: @item }
      when :stafftools
        render "stafftools/showcase_items/edit", locals: { collection: @collection, item: @item }
      else
        raise NotImplementedError
      end
    end
  end

  def update_item(item_path)
    if @item.update(item_hash)
      flash[:notice] = "#{@item} successfully updated"
      redirect_to [item_path, @collection]
    else
      flash[:error] = "Something went wrong there"

      case item_path
      when :biztools
        render "biztools/showcase_items/edit", locals: { collection: @collection, item: @item }
      when :stafftools
        render "stafftools/showcase_items/edit", locals: { collection: @collection, item: @item }
      else
        raise NotImplementedError
      end
    end
  end

  def edit_item(item_path)
    case item_path
    when :biztools
      render "biztools/showcase_items/edit", locals: { collection: @collection, item: @item }
    when :stafftools
      render "stafftools/showcase_items/edit", locals: { collection: @collection, item: @item }
    else
      raise NotImplementedError
    end
  end

  def destroy_item(item_path)
    @item.destroy
    flash[:notice] = "#{@item} removed from #{@collection}"
    redirect_to [item_path, @collection]
  end

  def perform_healthcheck
    repo = ::Repository.with_name_with_owner(params[:repo_name])

    if repo.present?
      community_profile = repo.community_profile || CommunityProfile.new

      render Stafftools::Explore::ShowcaseItems::HealthChecksComponent.new(
        community_profile: community_profile,
      ), layout: false
    else
      render html: "Repository not found."
    end
  end

  private

  def item_hash
    params.require(:showcase_item).permit(:name_with_owner, :body)
  end

  def find_item
    @item = ::Showcase::Item.find(params[:id])
  end

  def find_collection
    @collection = ::Showcase::Collection.find_by_slug!(params[:showcase_collection_id])
  end
end
