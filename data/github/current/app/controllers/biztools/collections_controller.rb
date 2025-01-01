# typed: false
# frozen_string_literal: true

class Biztools::CollectionsController < BiztoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  PER_PAGE = 30

  before_action :dotcom_required

  def index
    if params[:featured].present?
      featured = params[:featured].to_i == 1
    else
      featured = nil
    end

    collections = ::ExploreCollection
      .limit(1_000)
      .order(updated_at: :desc)
      .paginate(page: params[:page], per_page: PER_PAGE)

    unless featured.nil?
      if featured
        collections = collections.featured
      else
        collections = collections.non_featured
      end
    end

    if query = params[:q].presence
      collections = collections.with_name_like(query)
    end

    respond_to do |format|
      format.html do
        if request.xhr?
          render partial: "biztools/collections/curated_collections", locals: {
            featured: featured,
            query: query,
            collections: collections,
          }
        else
          render "biztools/collections/index", locals: {
            featured: featured,
            query: query,
            collections: collections,
            collections_repo: collections_repo,
          }
        end
      end
    end
  end

  def update
    collection = ExploreCollection.find_by!(slug: params[:collection])
    collection.featured = params[:featured].to_i == 1

    if !collection.save
      error = collection.errors.messages.values.join(", ")
      return render json: { error: error }, status: :unprocessable_entity
    end

    respond_to do |format|
      format.html do
        render partial: "biztools/collections/curated_collection", locals: { collection: collection }
      end
    end
  end

  def import # rubocop:todo GitHub/UseRestfulActions
    write_mode = params[:write_mode] == "1"
    dry_run = !write_mode

    repository_file_reader = ExploreRepositoryFileReader.new("collections")
    importer = CollectionImporter.new(repository_file_reader)
    import_result = importer.import(dry_run: dry_run, collection_slugs: params[:collections])

    unless import_result.any_changes?
      flash[:notice] = "Collections in GitHub are up-to-date with those in " +
                       "#{ExploreRepositoryFileReader.repository_name_with_owner}!"
      return redirect_to(biztools_collections_path)
    end

    if dry_run || importer.errors.any?
      render "biztools/collections/import", locals: {
        importer: importer,
        import_result: import_result,
        new_changesets: import_result.new_changesets,
        updated_changesets: import_result.updated_changesets,
        explore_repository: collections_repo,
      }
    else
      flash[:notice] = "Imported #{import_result.new_count} new collections(s), updated " \
                       "#{import_result.updated_count} collections(s), and deleted " \
                       "#{import_result.deleted_count} collection(s)."

      redirect_to biztools_collections_path
    end
  end

  private

  def collections_repo
    Repository.public_scope.with_name_with_owner(ExploreRepositoryFileReader.repository_name_with_owner)
  end
end
